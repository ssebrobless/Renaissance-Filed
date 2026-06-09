import SwiftUI

private enum MailRecencyFilter: String, CaseIterable, Identifiable {
    case currentWeek
    case recent30Days
    case recent90Days
    case allUnread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentWeek:
            return "Current Week"
        case .recent30Days:
            return "Recent 30d"
        case .recent90Days:
            return "Recent 90d"
        case .allUnread:
            return "All Unread"
        }
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .currentWeek:
            return calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        case .recent30Days:
            return calendar.date(byAdding: .day, value: -30, to: Date())
        case .recent90Days:
            return calendar.date(byAdding: .day, value: -90, to: Date())
        case .allUnread:
            return nil
        }
    }
}

struct MailReviewView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var recencyFilter: MailRecencyFilter = .currentWeek
    @State private var searchQuery = ""
    @State private var showRecentSent = false
    @State private var expandedMessageKey: String?

    private let sectionPreviewLimit = 18

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCards
                    guidanceCard
                    historyToolsSection

                    workSection

                    HStack(alignment: .top, spacing: 16) {
                        likelyJunkSection
                        otherUnreadSection
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            if model.mailReviewSettings.isEnabled,
               model.mailReviewSettings.autoRefreshOnLaunch,
               model.mailReviewSnapshot.scannedAt == nil {
                model.refreshMailReview()
            }
        }
        .onChange(of: recencyFilter) { _ in
            refreshHistoryViewsForActiveFilter()
        }
        .onChange(of: showRecentSent) { isEnabled in
            if isEnabled {
                model.loadRecentSentMail(since: recencyFilter.cutoffDate)
            } else {
                model.clearRecentSentMail()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mail Center")
                        .font(.title2.bold())
                    Text(model.mailReviewSettings.autoTrashStrongJunk
                         ? "Surface unread work mail first and auto-trash only strong junk matches."
                         : "Surface unread work-related emails first and flag junk conservatively.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                if let scannedAt = model.mailReviewSnapshot.scannedAt {
                    Text("Last scan: \(scannedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .padding(.top, 4)
                }
            }

            // Action buttons on their own row so they don't crowd the window edge.
            HStack(spacing: 8) {
                Button("Open Mail") {
                    model.openPreferredMailApp()
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(model.isPerformingMailReviewAction)

                Button("Mark Visible Read") {
                    model.markMailMessagesRead(visibleActionableMessages)
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(
                    model.isRefreshingMailReview ||
                    model.isPerformingMailReviewAction ||
                    !model.mailReviewSettings.isEnabled ||
                    visibleActionableMessages.isEmpty
                )

                Button("Trash Visible Junk") {
                    model.trashMailMessages(visibleLikelyJunkMessages)
                }
                .buttonStyle(.renaissanceSecondary)
                .tint(AppTheme.warn)
                .disabled(
                    model.isRefreshingMailReview ||
                    model.isPerformingMailReviewAction ||
                    !model.mailReviewSettings.isEnabled ||
                    visibleLikelyJunkMessages.isEmpty
                )

                Button("Mark All Inbox Read") {
                    model.markAllMailHistoryRead()
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(
                    model.isRefreshingMailReview ||
                    model.isPerformingMailReviewAction ||
                    !model.mailReviewSettings.isEnabled
                )

                Button("Empty Junk Folders") {
                    model.clearMailJunkFolder()
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(
                    model.isRefreshingMailReview ||
                    model.isPerformingMailReviewAction ||
                    !model.mailReviewSettings.isEnabled
                )

                Button("Refresh Mail") {
                    model.refreshMailReview()
                }
                .buttonStyle(.renaissancePrimary)
                .disabled(
                    model.isRefreshingMailReview ||
                    model.isPerformingMailReviewAction ||
                    !model.mailReviewSettings.isEnabled
                )
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Showing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink3)
                Picker("Mail recency", selection: $recencyFilter) {
                    ForEach(MailRecencyFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                if hiddenByRecencyCount > 0 {
                    Label("\(hiddenByRecencyCount) older hidden", systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }

                Spacer()
            }

            HStack(alignment: .center, spacing: 10) {
                TextField("Search sender, recipient, or subject", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runMailSearch()
                    }

                Button("Search") {
                    runMailSearch()
                }
                .buttonStyle(.renaissancePrimary)
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSearchingMailHistory)

                Button("Clear Search") {
                    searchQuery = ""
                    model.clearMailHistorySearch()
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(searchQuery.isEmpty && model.mailHistorySearchResults.isEmpty)

                Toggle(isOn: $showRecentSent) {
                    Text("Show Recent Sent")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)
                .frame(width: 170, alignment: .leading)

                Spacer()
            }
        }
        .padding(20)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            statCard(title: "Work Unread", value: "\(filteredPriorityMessages.count)", color: .blue)
            statCard(title: "Likely Junk", value: "\(filteredLikelyJunkMessages.count)", color: AppTheme.warn)
            statCard(title: "Other Unread", value: "\(filteredOtherMessages.count)", color: .secondary)
            statCard(title: "Total Visible", value: "\(filteredTotalCount)", color: AppTheme.warn)
        }
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How This Works", systemImage: "envelope.badge")
                .font(.headline)
            Text(model.mailReviewSettings.autoTrashStrongJunk
                 ? "The app reads recent unread messages from your selected mail provider, sorts them newest-first, flags likely work mail, and lets you bulk-clear likely junk."
                 : "The app reads recent unread messages from your selected mail provider, sorts them newest-first, flags likely work mail, and separately flags likely junk with conservative rules.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink3)
            Text("Default focus: current week. Switch to All Unread if you want to review older inbox history.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text("Preferred send app: \(model.mailReviewSettings.preferredProvider.title)")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            if let diagnostic = model.mailReviewSnapshot.diagnosticMessage, !diagnostic.isEmpty {
                Label(diagnostic, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warn)
            }
            if !model.mailReviewLastError.isEmpty {
                Label(model.mailReviewLastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.bad)
            }
            if model.isRefreshingMailReview {
                Text("Scanning Mail now...")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            } else if model.isPerformingMailReviewAction {
                Text("Updating Mail now...")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .padding()
        .background(AppTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var historyToolsSection: some View {
        if shouldShowHistoryPanels {
            HStack(alignment: .top, spacing: 16) {
                if shouldShowSearchPanel {
                    historySectionCard(
                        title: "Mail Search",
                        subtitle: "Results are filtered by \(recencyFilter.title.lowercased()) and search inbox plus sent mail.",
                        messages: model.mailHistorySearchResults,
                        isLoading: model.isSearchingMailHistory,
                        emptyTitle: "No Matching Mail",
                        emptyMessage: "Try a sender name, recipient email, vendor name, or subject keyword."
                    )
                }

                if shouldShowRecentSentPanel {
                    historySectionCard(
                        title: "Recently Sent",
                        subtitle: "Sent messages from your father filtered by \(recencyFilter.title.lowercased()).",
                        messages: model.mailRecentSentMessages,
                        isLoading: model.isLoadingRecentSentMail,
                        emptyTitle: "No Recent Sent Mail",
                        emptyMessage: "No sent messages were found in this date window."
                    )
                }
            }
        }
    }

    private var workSection: some View {
        sectionCard(
            title: "Work-Related Unread",
            subtitle: "Matched from customer emails and your VIP sender/domain list.",
            messages: visiblePriorityMessages,
            totalCount: filteredPriorityMessages.count,
            badgeColor: .blue,
            emptyTitle: "No Work-Related Unread",
            emptyMessage: model.mailReviewSettings.isEnabled
                ? "No recent unread messages currently match your customer or VIP sender rules."
                : "Enable Mail Review in Settings to scan unread messages."
        ) {
            if !visiblePriorityMessages.isEmpty {
                Button("Mark Visible Read") {
                    model.markMailMessagesRead(visiblePriorityMessages)
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(model.isPerformingMailReviewAction)
            }
        }
    }

    private var likelyJunkSection: some View {
        sectionCard(
            title: "Likely Junk / Promotional",
            subtitle: model.mailReviewSettings.autoTrashStrongJunk
                ? "Recent junk-style messages that were not strong enough for auto-trash."
                : "Recent junk-style messages. Review before clearing.",
            messages: visibleLikelyJunkMessages,
            totalCount: filteredLikelyJunkMessages.count,
            badgeColor: .orange,
            emptyTitle: "No Likely Junk Flagged",
            emptyMessage: "No recent unread messages currently match the junk heuristics."
        ) {
            if !visibleLikelyJunkMessages.isEmpty {
                Button("Trash Visible") {
                    model.trashMailMessages(visibleLikelyJunkMessages)
                }
                .buttonStyle(.renaissanceSecondary)
                .tint(AppTheme.warn)
                .disabled(model.isPerformingMailReviewAction)

                Button("Mark Visible Read") {
                    model.markMailMessagesRead(visibleLikelyJunkMessages)
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(model.isPerformingMailReviewAction)
            }
        }
    }

    private var otherUnreadSection: some View {
        sectionCard(
            title: "Other Unread",
            subtitle: "Recent unread mail that did not match a work sender rule.",
            messages: visibleOtherMessages,
            totalCount: filteredOtherMessages.count,
            badgeColor: .secondary,
            emptyTitle: "No Other Unread",
            emptyMessage: "No recent unread messages are currently visible for this filter."
        ) {
            if !visibleOtherMessages.isEmpty {
                Button("Mark Visible Read") {
                    model.markMailMessagesRead(visibleOtherMessages)
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(model.isPerformingMailReviewAction)
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Actions: View>(
        title: String,
        subtitle: String,
        messages: [MailInboxMessage],
        totalCount: Int,
        badgeColor: Color,
        emptyTitle: String,
        emptyMessage: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                HStack(spacing: 8) {
                    actions()
                }
            }

            if messages.isEmpty {
                emptySection(title: emptyTitle, message: emptyMessage)
            } else {
                ForEach(messages) { message in
                    compactMessageCard(message: message, badgeColor: badgeColor)
                }
                if totalCount > messages.count {
                    Text("+ \(totalCount - messages.count) more in this section")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func compactMessageCard(message: MailInboxMessage, badgeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.senderName.isEmpty ? (message.senderEmail.isEmpty ? "Unknown Sender" : message.senderEmail) : message.senderName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !message.senderEmail.isEmpty {
                        Text(message.senderEmail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(message.receivedAtText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .multilineTextAlignment(.trailing)
            }

            Text(message.subject)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let reason = message.priorityReason {
                    miniBadge(text: reason, color: .blue, systemImage: "star.fill")
                }
                if let junkReason = message.junkReason {
                    miniBadge(text: junkReason, color: .orange, systemImage: "exclamationmark.triangle.fill")
                }
                if message.isStrongLikelyJunk {
                    miniBadge(text: "Strong junk", color: .red, systemImage: "trash.fill")
                }
                if !message.mailbox.isEmpty {
                    miniBadge(text: message.mailbox, color: .secondary, systemImage: "tray")
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Spacer()
                Button(isExpanded(message) ? "Hide Body" : "View Body") {
                    toggleExpandedBody(for: message)
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(model.isPerformingMailReviewAction)
                if message.supportsDirectActions {
                    if message.isLikelyJunk {
                        Button("Trash") {
                            model.trashMailMessage(message)
                        }
                        .buttonStyle(.renaissanceSecondary)
                        .tint(AppTheme.warn)
                        .disabled(model.isPerformingMailReviewAction)
                    }
                    Button("Mark Read") {
                        model.markMailMessageRead(message)
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(model.isPerformingMailReviewAction)
                    Button("Open") {
                        model.openMailMessage(message)
                    }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(model.isPerformingMailReviewAction)
                } else {
                    Button("Open Mail") {
                        model.openMailMessage(message)
                    }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(model.isPerformingMailReviewAction)
                }
            }

            if isExpanded(message) {
                bodyPreview(key: model.mailBodyKey(for: message))
            }
        }
        .padding(12)
        .background(badgeColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func historySectionCard(
        title: String,
        subtitle: String,
        messages: [MailHistoryMessage],
        isLoading: Bool,
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink3)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if messages.isEmpty {
                emptySection(title: emptyTitle, message: emptyMessage)
            } else {
                ForEach(messages) { message in
                    historyMessageCard(message)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func historyMessageCard(_ message: MailHistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(historyParticipantTitle(for: message))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !message.participantEmail.isEmpty,
                       message.participantEmail.caseInsensitiveCompare(message.participantDisplay) != .orderedSame {
                        Text(message.participantEmail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(message.dateText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .multilineTextAlignment(.trailing)
            }

            Text(message.subject)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 8) {
                miniBadge(
                    text: message.direction == .sent ? "Sent" : "Inbox",
                    color: message.direction == .sent ? AppTheme.ok : .blue,
                    systemImage: message.direction == .sent ? "paperplane.fill" : "tray.fill"
                )
                if !message.mailbox.isEmpty {
                    miniBadge(text: message.mailbox, color: .secondary, systemImage: "tray")
                }
                if !message.accountName.isEmpty {
                    miniBadge(text: message.accountName, color: .secondary, systemImage: "person.crop.circle")
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button(isExpanded(message) ? "Hide Body" : "View Body") {
                    toggleExpandedBody(for: message)
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(model.isPerformingMailReviewAction)
                Button("Open") {
                    model.openMailHistoryMessage(message)
                }
                .buttonStyle(.renaissancePrimary)
                .disabled(model.isPerformingMailReviewAction)
            }

            if isExpanded(message) {
                bodyPreview(key: model.mailBodyKey(for: message))
            }
        }
        .padding(12)
        .background(AppTheme.accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func bodyPreview(key: String) -> some View {
        Group {
            if model.mailBodyLoadingKey == key && model.mailBodyCache[key] == nil {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading body text...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let body = model.mailBodyCache[key], !body.isEmpty {
                ScrollView {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 90, maxHeight: 180)
                .padding(10)
                .background(AppTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func miniBadge(text: String, color: Color, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func emptySection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filteredPriorityMessages: [MailInboxMessage] {
        filteredMessages(from: model.mailReviewSnapshot.priorityMessages)
    }

    private var filteredLikelyJunkMessages: [MailInboxMessage] {
        filteredMessages(from: model.mailReviewSnapshot.likelyJunkMessages)
    }

    private var filteredOtherMessages: [MailInboxMessage] {
        filteredMessages(from: model.mailReviewSnapshot.otherMessages)
    }

    private var visiblePriorityMessages: [MailInboxMessage] {
        Array(filteredPriorityMessages.prefix(sectionPreviewLimit))
    }

    private var visibleLikelyJunkMessages: [MailInboxMessage] {
        Array(filteredLikelyJunkMessages.prefix(sectionPreviewLimit))
    }

    private var visibleOtherMessages: [MailInboxMessage] {
        Array(filteredOtherMessages.prefix(max(sectionPreviewLimit, model.mailReviewSettings.maxOtherUnread)))
    }

    private var visibleActionableMessages: [MailInboxMessage] {
        (visiblePriorityMessages + visibleLikelyJunkMessages + visibleOtherMessages).filter(\.supportsDirectActions)
    }

    private var filteredTotalCount: Int {
        filteredPriorityMessages.count + filteredLikelyJunkMessages.count + filteredOtherMessages.count
    }

    private var hiddenByRecencyCount: Int {
        max(model.mailReviewSnapshot.totalUnread - filteredTotalCount, 0)
    }

    private var shouldShowSearchPanel: Bool {
        model.isSearchingMailHistory ||
        !model.mailHistorySearchResults.isEmpty ||
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowRecentSentPanel: Bool {
        showRecentSent || model.isLoadingRecentSentMail || !model.mailRecentSentMessages.isEmpty
    }

    private var shouldShowHistoryPanels: Bool {
        shouldShowSearchPanel || shouldShowRecentSentPanel
    }

    private func filteredMessages(from messages: [MailInboxMessage]) -> [MailInboxMessage] {
        messages
            .filter(shouldInclude)
            .sorted { lhs, rhs in
                switch (lhs.receivedAt, rhs.receivedAt) {
                case let (left?, right?):
                    if left != right { return left > right }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                if lhs.receivedAtText != rhs.receivedAtText {
                    return lhs.receivedAtText > rhs.receivedAtText
                }
                return lhs.id > rhs.id
            }
    }

    private func shouldInclude(_ message: MailInboxMessage) -> Bool {
        guard let cutoffDate = recencyFilter.cutoffDate else { return true }
        guard let receivedAt = message.receivedAt else { return false }
        return receivedAt >= cutoffDate
    }

    private func runMailSearch() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            model.clearMailHistorySearch()
            return
        }
        model.searchMailHistory(query: trimmedQuery, since: recencyFilter.cutoffDate)
    }

    private func refreshHistoryViewsForActiveFilter() {
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runMailSearch()
        } else {
            model.clearMailHistorySearch()
        }

        if showRecentSent {
            model.loadRecentSentMail(since: recencyFilter.cutoffDate)
        } else {
            model.clearRecentSentMail()
        }
    }

    private func historyParticipantTitle(for message: MailHistoryMessage) -> String {
        let display = message.participantDisplay.isEmpty
            ? (message.participantEmail.isEmpty ? "Unknown Contact" : message.participantEmail)
            : message.participantDisplay
        let prefix = message.direction == .sent ? "To" : "From"
        return "\(prefix): \(display)"
    }

    private func isExpanded(_ message: MailInboxMessage) -> Bool {
        expandedMessageKey == model.mailBodyKey(for: message)
    }

    private func isExpanded(_ message: MailHistoryMessage) -> Bool {
        expandedMessageKey == model.mailBodyKey(for: message)
    }

    private func toggleExpandedBody(for message: MailInboxMessage) {
        let key = model.mailBodyKey(for: message)
        if expandedMessageKey == key {
            expandedMessageKey = nil
        } else {
            expandedMessageKey = key
            model.loadMailBodyIfNeeded(for: message)
        }
    }

    private func toggleExpandedBody(for message: MailHistoryMessage) {
        let key = model.mailBodyKey(for: message)
        if expandedMessageKey == key {
            expandedMessageKey = nil
        } else {
            expandedMessageKey = key
            model.loadMailBodyIfNeeded(for: message)
        }
    }
}
