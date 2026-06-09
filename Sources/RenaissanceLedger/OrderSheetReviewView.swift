import AppKit
import SwiftUI

struct PendingOrderSheetQueueView: View {
    let rows: [OrderSheetRow]
    var onReview: (OrderSheetRow) -> Void
    var onOpenImage: (OrderSheetRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pending Order Sheets")
                        .font(.headline)
                    Text("Imported sheets stay outside the official ledger until approved.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                Text("\(rows.count)")
                    .font(.title3.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            ForEach(rows.prefix(5)) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.originalFilename)
                            .font(.subheadline.weight(.medium))
                        Text(row.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Spacer()
                    Button("Open File") { onOpenImage(row) }
                        .buttonStyle(.borderless)
                    Button("Review") { onReview(row) }
                        .buttonStyle(.renaissancePrimary)
                }
                if row.id != rows.prefix(5).last?.id {
                    Divider()
                }
            }

            if rows.count > 5 {
                Text("+ \(rows.count - 5) more pending sheets")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .padding()
        .background(AppTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyOrderSheetQueueView: View {
    var onScanNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Order Sheet Inbox")
                        .font(.headline)
                    Text("No pending sheets yet. If you just shared one from your phone, scan the inbox now.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                Button("Scan Phone Inbox") { onScanNow() }
                    .buttonStyle(.renaissanceSecondary)
            }
        }
        .padding()
        .background(AppTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct OrderSheetReviewView: View {
    @EnvironmentObject private var model: AppViewModel

    let orderSheet: OrderSheetRow
    var onFinish: () -> Void

    @State private var selectedCustomerID: Int64 = 0
    @State private var issueDate = Date()
    @State private var validUntil = Date().addingTimeInterval(30 * 86_400)
    @State private var status = "draft"
    @State private var memo = ""
    @State private var lines: [InvoiceLineEntry] = [InvoiceLineEntry()]
    @State private var zoom: Double = 1
    @State private var sourceImage: NSImage?
    @State private var ocrLines: [OrderSheetOCRLine] = []
    @State private var errorMessage = ""
    @State private var didInitialize = false
    @State private var finalized = false
    @State private var isSaving = false
    @State private var isRefreshingOCR = false
    @State private var showApproveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private let statusOptions = ["draft", "sent", "accepted", "converted", "historical"]

    private var total: Double { lines.reduce(0) { $0 + $1.amount } }
    private var hasValidDraft: Bool {
        selectedCustomerID != 0 && !validatedLines.isEmpty
    }
    private var validatedLines: [InvoiceLineEntry] {
        lines.filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount > 0 }
    }
    private var ocrTranscript: String {
        ocrLines.map(\.text).joined(separator: "\n")
    }
    private var ocrSummary: String {
        let trimmed = ocrLines
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(trimmed.prefix(4)).joined(separator: "  •  ")
    }
    private var hasMeaningfulLineContent: Bool {
        lines.contains { line in
            line.selectedItemID != 0
                || !line.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || line.quantity.trimmingCharacters(in: .whitespacesAndNewlines) != "1"
                || !line.rate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    private var hasMeaningfulDraftContent: Bool {
        selectedCustomerID != 0
            || !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasMeaningfulLineContent
    }
    private var visibleDraftPreviewLines: [InvoiceLineEntry] {
        lines.filter {
            !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.amount > 0
        }
    }
    private var approvalTestingModeEnabled: Bool {
        model.orderSheetApprovalSettings.testingModeEnabled
    }
    private var requireApprovalConfirmation: Bool {
        model.orderSheetApprovalSettings.requireConfirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Order Sheet")
                        .font(.title2.bold())
                    Text(orderSheet.originalFilename)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink3)
                    Text("Estimate number will be assigned only after approval.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.bad)
                }
                Button("Discard") { discard() }
                    .disabled(isSaving)
                Button("Save Draft") { saveDraft(status: .inReview) }
                    .disabled(isSaving)
                Button("Auto-Fill Draft") { applySuggestedDraftIfAppropriate(force: true) }
                    .disabled(isSaving || (ocrLines.isEmpty && !isRefreshingOCR))
                Button("Approve & Create Estimate") { beginApproval() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(isSaving || !hasValidDraft || approvalTestingModeEnabled)
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            HSplitView {
                imagePane
                    .frame(minWidth: 360, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                rightPane
                    .frame(minWidth: 460, idealWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .onAppear { setup() }
        .onDisappear { autosaveIfNeeded() }
        .alert("Create Official Estimate?", isPresented: $showApproveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Create Estimate") { approve() }
        } message: {
            Text("This will create a real estimate in the official business ledger from the current staged draft.")
        }
        .accessibilityIdentifier("orderSheet.review.\(orderSheet.id)")
    }

    private var imagePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source Preview")
                    .font(.headline)
                Spacer()
                Text("Zoom")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                Slider(value: $zoom, in: 0.5...2.5)
                    .frame(width: 140)
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.ink3)
                    .frame(width: 46, alignment: .trailing)
            }

            ScrollView([.horizontal, .vertical]) {
                if let sourceImage {
                    Image(nsImage: sourceImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            width: max(320, sourceImage.size.width * zoom),
                            height: max(320, sourceImage.size.height * zoom)
                        )
                        .padding()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 42))
                            .foregroundStyle(AppTheme.ink3)
                    Text("Preview unavailable")
                            .foregroundStyle(AppTheme.ink3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    workflowExplanationCard
                    draftPreviewCard

                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Customer")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            Picker("", selection: $selectedCustomerID) {
                                Text("- Select Customer -").tag(Int64(0))
                                ForEach(model.customers) { customer in
                                    Text(customer.displayLabel + (customer.company.isEmpty ? "" : " - " + customer.company))
                                        .tag(customer.id)
                                }
                            }
                            .frame(width: 280)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            SmartDateField(date: $issueDate)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Valid Until")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            SmartDateField(date: $validUntil)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            Picker("", selection: $status) {
                                ForEach(statusOptions, id: \.self) { option in
                                    Text(option.capitalized).tag(option)
                                }
                            }
                            .frame(width: 140)
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("ITEM").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 130, alignment: .leading)
                            Text("DESCRIPTION").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                            Text("QTY").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 60, alignment: .trailing)
                            Text("RATE").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .trailing)
                            Text("AMOUNT").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
                            Spacer().frame(width: 30)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(AppTheme.surface)

                        Divider()

                        ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                            EstimateLineEditorRow(
                                line: $line,
                                rowIndex: index,
                                serviceItems: model.serviceItems
                            ) {
                                if lines.count > 1 {
                                    lines.removeAll { $0.id == line.id }
                                }
                            }
                            Divider()
                        }

                        Button("+ Add Line") {
                            lines.append(InvoiceLineEntry())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .background(AppTheme.canvas)
                    .cornerRadius(8)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                                Spacer()
                                Button("Use OCR as Notes") {
                                    useOCRAsNotes()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .disabled(ocrTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            TextField("", text: $memo, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(4)
                                .frame(maxWidth: .infinity)
                        }

                        Spacer(minLength: 20)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("ESTIMATE TOTAL")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink3)
                            Text(estimateCurrency(total))
                                .font(.title2.bold())
                        }
                        .padding()
                        .background(AppTheme.surface)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OCR Transcript")
                        .font(.headline)
                    Spacer()
                    if isRefreshingOCR {
                        Text("Refreshing...")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Text("\(ocrLines.count) line\(ocrLines.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                ScrollView {
                    Text(ocrTranscript.isEmpty ? "No text detected." : ocrTranscript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .frame(minHeight: 180)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding([.horizontal, .bottom])
        }
    }

    private var workflowExplanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What The App Did", systemImage: "doc.text.viewfinder")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Copied the original file into private staging storage on this Mac.")
                Text("2. Extracted OCR text for reference. The transcript is shown below.")
                Text("3. Suggested a draft estimate from OCR only when the draft was blank or you request Auto-Fill.")
                Text("4. Handwritten selection marks are treated as review hints unless you choose to edit the draft fields.")
                Text("5. Did not change estimates, reports, or official business data yet.")
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.ink3)

            if approvalTestingModeEnabled {
                Label("Testing mode is on. Approve & Create Estimate is disabled until you turn testing mode off in Settings.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warn)
            } else if requireApprovalConfirmation {
                Label("Creating an official estimate will always ask for confirmation first.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            if !ocrSummary.isEmpty {
                Text("OCR preview: \(ocrSummary)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .textSelection(.enabled)
            }

            Text("Fill or edit the draft on this screen, then click Approve & Create Estimate only when it looks correct.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding()
        .background(AppTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var draftPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Draft Preview", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(visibleDraftPreviewLines.count) line\(visibleDraftPreviewLines.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            if visibleDraftPreviewLines.isEmpty {
                Text("No suggested lines yet. Use Auto-Fill Draft after OCR finishes, or enter the estimate manually.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            } else {
                ForEach(Array(visibleDraftPreviewLines.enumerated()), id: \.element.id) { index, line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(index + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.ink3)
                            Text(line.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Line" : line.itemName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(line.quantity) x \(line.rate.isEmpty ? "0.00" : line.rate) = \(estimateCurrency(line.amount))")
                                .font(.caption.monospaced())
                                .foregroundStyle(AppTheme.ink3)
                        }
                        Text(line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description yet." : line.description)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                        if !line.reviewHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label(line.reviewHint, systemImage: "highlighter")
                                .font(.caption)
                                .foregroundStyle(AppTheme.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if index < visibleDraftPreviewLines.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func setup() {
        guard !didInitialize else { return }
        didInitialize = true

        model.markOrderSheetInReview(id: orderSheet.id)

        let draft = orderSheet.reviewDraft
        if let customerID = draft.customerID {
            selectedCustomerID = customerID
        }
        issueDate = DateFormatter.isoDate.date(from: draft.issueDate) ?? Date()
        validUntil = DateFormatter.isoDate.date(from: draft.validUntil) ?? issueDate.addingTimeInterval(30 * 86_400)
        status = draft.status
        memo = draft.memo
        let draftLines = draft.lines.isEmpty ? [.blank()] : draft.lines
        lines = draftLines.map { $0.asInvoiceLineEntry() }
        sourceImage = OrderSheetOCR.previewImage(for: orderSheet.imageURL)
        ocrLines = orderSheet.ocrLines
        applySuggestedDraftIfAppropriate(force: false)
        refreshOCRIfNeeded()
    }

    private func currentDraft() -> OrderSheetReviewDraft {
        OrderSheetReviewDraft(
            customerID: selectedCustomerID == 0 ? nil : selectedCustomerID,
            issueDate: DateFormatter.isoDate.string(from: issueDate),
            validUntil: DateFormatter.isoDate.string(from: validUntil),
            memo: memo,
            status: status,
            lines: lines.map(OrderSheetDraftLine.from)
        )
    }

    private func autosaveIfNeeded() {
        guard !finalized else { return }
        do {
            try model.saveOrderSheetDraft(orderSheetID: orderSheet.id, draft: currentDraft(), status: .inReview)
        } catch {
            model.statusMessage = "Order sheet autosave failed: \(error.localizedDescription)"
        }
    }

    private func saveDraft(status: OrderSheetStatus) {
        isSaving = true
        defer { isSaving = false }
        do {
            try model.saveOrderSheetDraft(orderSheetID: orderSheet.id, draft: currentDraft(), status: status)
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard() {
        isSaving = true
        defer { isSaving = false }
        do {
            finalized = true
            try model.discardOrderSheet(orderSheetID: orderSheet.id, draft: currentDraft())
            onFinish()
            dismiss()
        } catch {
            finalized = false
            errorMessage = error.localizedDescription
        }
    }

    private func beginApproval() {
        guard !approvalTestingModeEnabled else {
            errorMessage = OrderSheetApprovalError.testingModeEnabled.localizedDescription
            return
        }
        if requireApprovalConfirmation {
            showApproveConfirmation = true
        } else {
            approve()
        }
    }

    private func approve() {
        isSaving = true
        defer { isSaving = false }
        do {
            let createdEstimate = try model.approveOrderSheetToEstimate(orderSheetID: orderSheet.id, draft: currentDraft())
            finalized = true
            errorMessage = ""
            model.statusMessage = "Created estimate \(createdEstimate.number) from order sheet \(orderSheet.originalFilename)."
            onFinish()
            dismiss()
        } catch {
            finalized = false
            errorMessage = error.localizedDescription
        }
    }

    private func useOCRAsNotes() {
        let transcript = ocrTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        memo = transcript
    }

    private func applySuggestedDraftIfAppropriate(force: Bool) {
        guard force || !hasMeaningfulDraftContent else { return }
        guard let suggestion = OrderSheetDraftSuggestionService.suggestDraft(
            ocrLines: ocrLines,
            customers: model.customers,
            serviceItems: model.serviceItems,
            companyName: model.companyInfo.name,
            referenceDate: issueDate,
            preferredStatus: status
        ) else {
            if force {
                errorMessage = "Could not build a draft suggestion from the current OCR yet."
            }
            return
        }

        let formatter = DateFormatter.isoDate
        let suggestionHasMeaningfulLines = suggestion.lines.contains { line in
            line.selectedItemID != 0
                || !line.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || line.quantity.trimmingCharacters(in: .whitespacesAndNewlines) != "1"
                || !line.rate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let suggestionMemo = suggestion.memo.trimmingCharacters(in: .whitespacesAndNewlines)

        if let customerID = suggestion.customerID {
            selectedCustomerID = customerID
        }
        if let parsedIssueDate = formatter.date(from: suggestion.issueDate) {
            issueDate = parsedIssueDate
        }
        if let parsedValidUntil = formatter.date(from: suggestion.validUntil) {
            validUntil = parsedValidUntil
        }
        if !suggestionMemo.isEmpty && (force || memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            memo = suggestion.memo
        }
        if suggestionHasMeaningfulLines && (force || !hasMeaningfulLineContent) {
            let suggestedLines = suggestion.lines.isEmpty ? [.blank()] : suggestion.lines
            lines = suggestedLines.map { $0.asInvoiceLineEntry() }
        }
        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = suggestion.status
        }

        try? model.saveOrderSheetDraft(orderSheetID: orderSheet.id, draft: currentDraft(), status: .inReview)
        if force {
            errorMessage = ""
        }
    }

    private func refreshOCRIfNeeded() {
        let shouldRefresh = orderSheet.imageURL.pathExtension.lowercased() == "pdf" || ocrLines.isEmpty
        guard shouldRefresh, !isRefreshingOCR else { return }
        isRefreshingOCR = true

        let fileURL = orderSheet.imageURL
        let orderSheetID = orderSheet.id
        DispatchQueue.global(qos: .userInitiated).async {
            let refreshedLines = (try? OrderSheetOCR.recognizeLines(in: fileURL)) ?? []
            DispatchQueue.main.async {
                self.isRefreshingOCR = false
                guard !refreshedLines.isEmpty else { return }
                self.ocrLines = refreshedLines
                try? self.model.saveOrderSheetOCR(orderSheetID: orderSheetID, ocrLines: refreshedLines)
                self.applySuggestedDraftIfAppropriate(force: false)
            }
        }
    }
}
