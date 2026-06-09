import AppKit
import Foundation
import SQLite3

struct MailReviewSettings: Codable, Hashable {
    var preferredProvider: MailProviderKind
    var isEnabled: Bool
    var autoRefreshOnLaunch: Bool
    var includeCustomerEmails: Bool
    var vipSenderEmails: String
    var vipSenderDomains: String
    var scanLikelyJunk: Bool
    var autoTrashStrongJunk: Bool
    var junkSenderEmails: String
    var junkSenderDomains: String
    var junkSubjectKeywords: String
    var maxOtherUnread: Int

    static func load() -> MailReviewSettings {
        let defaults = UserDefaults.standard
        return MailReviewSettings(
            preferredProvider: MailProviderKind(rawValue: defaults.string(forKey: "mailReview.preferredProvider") ?? "") ?? .appleMail,
            isEnabled: defaults.object(forKey: "mailReview.isEnabled") as? Bool ?? true,
            autoRefreshOnLaunch: defaults.object(forKey: "mailReview.autoRefreshOnLaunch") as? Bool ?? true,
            includeCustomerEmails: defaults.object(forKey: "mailReview.includeCustomerEmails") as? Bool ?? true,
            vipSenderEmails: defaults.string(forKey: "mailReview.vipSenderEmails") ?? "",
            vipSenderDomains: defaults.string(forKey: "mailReview.vipSenderDomains") ?? "",
            scanLikelyJunk: defaults.object(forKey: "mailReview.scanLikelyJunk") as? Bool ?? true,
            autoTrashStrongJunk: defaults.object(forKey: "mailReview.autoTrashStrongJunk") as? Bool ?? true,
            junkSenderEmails: defaults.string(forKey: "mailReview.junkSenderEmails") ?? "",
            junkSenderDomains: defaults.string(forKey: "mailReview.junkSenderDomains") ?? "",
            junkSubjectKeywords: defaults.string(forKey: "mailReview.junkSubjectKeywords") ?? "unsubscribe, sale, promo, promotion, newsletter, special offer, deal, limited time, coupon, clearance",
            maxOtherUnread: max(5, defaults.object(forKey: "mailReview.maxOtherUnread") as? Int ?? 20)
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(preferredProvider.rawValue, forKey: "mailReview.preferredProvider")
        defaults.set(isEnabled, forKey: "mailReview.isEnabled")
        defaults.set(autoRefreshOnLaunch, forKey: "mailReview.autoRefreshOnLaunch")
        defaults.set(includeCustomerEmails, forKey: "mailReview.includeCustomerEmails")
        defaults.set(vipSenderEmails, forKey: "mailReview.vipSenderEmails")
        defaults.set(vipSenderDomains, forKey: "mailReview.vipSenderDomains")
        defaults.set(scanLikelyJunk, forKey: "mailReview.scanLikelyJunk")
        defaults.set(autoTrashStrongJunk, forKey: "mailReview.autoTrashStrongJunk")
        defaults.set(junkSenderEmails, forKey: "mailReview.junkSenderEmails")
        defaults.set(junkSenderDomains, forKey: "mailReview.junkSenderDomains")
        defaults.set(junkSubjectKeywords, forKey: "mailReview.junkSubjectKeywords")
        defaults.set(maxOtherUnread, forKey: "mailReview.maxOtherUnread")
    }

    var normalizedVIPEmails: Set<String> {
        Set(parseList(vipSenderEmails).map { $0.lowercased() })
    }

    var normalizedVIPDomains: Set<String> {
        Set(parseList(vipSenderDomains).map { value in
            let lowered = value.lowercased()
            return lowered.hasPrefix("@") ? String(lowered.dropFirst()) : lowered
        })
    }

    var normalizedJunkEmails: Set<String> {
        Set(parseList(junkSenderEmails).map { $0.lowercased() })
    }

    var normalizedJunkDomains: Set<String> {
        Set(parseList(junkSenderDomains).map { value in
            let lowered = value.lowercased()
            return lowered.hasPrefix("@") ? String(lowered.dropFirst()) : lowered
        })
    }

    var normalizedJunkSubjectKeywords: [String] {
        parseList(junkSubjectKeywords).map { $0.lowercased() }
    }

    private func parseList(_ raw: String) -> [String] {
        raw
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct MailInboxMessage: Identifiable, Hashable {
    let id: Int64
    let provider: MailProviderKind
    let senderName: String
    let senderEmail: String
    let subject: String
    let mailbox: String
    let receivedAtText: String
    let receivedAt: Date?
    let isPriority: Bool
    let priorityReason: String?
    let isLikelyJunk: Bool
    let isStrongLikelyJunk: Bool
    let junkReason: String?
    let supportsDirectActions: Bool
}

enum MailHistoryDirection: String, Hashable {
    case inbox
    case sent

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        }
    }
}

struct MailHistoryMessage: Identifiable, Hashable {
    let id: Int64
    let provider: MailProviderKind
    let direction: MailHistoryDirection
    let accountName: String
    let mailbox: String
    let participantDisplay: String
    let participantEmail: String
    let subject: String
    let dateText: String
    let date: Date?
}

struct MailInboxSnapshot: Hashable {
    var priorityMessages: [MailInboxMessage] = []
    var likelyJunkMessages: [MailInboxMessage] = []
    var otherMessages: [MailInboxMessage] = []
    var scannedAt: Date? = nil
    var diagnosticMessage: String? = nil

    static let empty = MailInboxSnapshot()

    var priorityCount: Int { priorityMessages.count }
    var likelyJunkCount: Int { likelyJunkMessages.count }
    var otherCount: Int { otherMessages.count }
    var totalUnread: Int { priorityMessages.count + likelyJunkMessages.count + otherMessages.count }
    var allMessages: [MailInboxMessage] { priorityMessages + likelyJunkMessages + otherMessages }
    var actionableMessages: [MailInboxMessage] { allMessages.filter(\.supportsDirectActions) }
}

struct MailReviewRefreshResult: Hashable {
    var snapshot: MailInboxSnapshot
    var autoTrashedCount: Int = 0
    var autoTrashFailureCount: Int = 0
}

enum MailReviewServiceError: LocalizedError {
    case automationFailed(String)
    case automationTimedOut(String)
    case localIndexUnavailable(String)
    case messageNotFound

    var errorDescription: String? {
        switch self {
        case .automationFailed(let message):
            return message
        case .automationTimedOut(let message):
            return message
        case .localIndexUnavailable(let message):
            return message
        case .messageNotFound:
            return "That Mail message could not be found."
        }
    }
}

enum MailReviewService {
    private static let fieldSeparator = Character(UnicodeScalar(31)!)
    private static let recordSeparator = Character(UnicodeScalar(30)!)
    private static let automationTimeoutSeconds: TimeInterval = 12
    private static let maxLiveAppleMailMessages = 75
    private static let maxIndexedMessages = 250

    private struct JunkAssessment {
        let reason: String
        let isStrong: Bool
    }

    private struct MailFetchContext {
        let provider: MailProviderKind
        let rawMessages: [RawMailMessage]
        let supportsDirectActions: Bool
        let diagnosticMessage: String?
    }

    static func refreshUnreadMessages(
        settings: MailReviewSettings,
        customers: [CustomerRow]
    ) throws -> MailReviewRefreshResult {
        let provider = resolvedProvider(for: settings)
        var snapshot = try fetchUnreadMessages(settings: settings, customers: customers)
        var autoTrashedCount = 0
        var autoTrashFailureCount = 0

        if settings.autoTrashStrongJunk {
            let candidates = snapshot.likelyJunkMessages.filter(\.isStrongLikelyJunk)
            for message in candidates {
                do {
                    try trashMessage(message)
                    autoTrashedCount += 1
                } catch MailReviewServiceError.messageNotFound {
                    continue
                } catch {
                    autoTrashFailureCount += 1
                }
            }

            do {
                autoTrashedCount += try clearJunkFolderIfNeeded(using: provider)
            } catch {
                autoTrashFailureCount += 1
            }

            if autoTrashedCount > 0 {
                snapshot = try fetchUnreadMessages(settings: settings, customers: customers)
            }
        }

        return MailReviewRefreshResult(
            snapshot: snapshot,
            autoTrashedCount: autoTrashedCount,
            autoTrashFailureCount: autoTrashFailureCount
        )
    }

    static func fetchUnreadMessages(
        settings: MailReviewSettings,
        customers: [CustomerRow]
    ) throws -> MailInboxSnapshot {
        let context = try fetchUnreadMessagesWithFallback(settings: settings)
        let provider = context.provider
        let rawMessages = context.rawMessages
        let customerEmailSet = settings.includeCustomerEmails
            ? Set(customers.flatMap { normalizedRecipientEmails(from: $0.email) }.map { $0.lowercased() })
            : []
        let vipEmails = settings.normalizedVIPEmails
        let vipDomains = settings.normalizedVIPDomains
        let junkEmails = settings.normalizedJunkEmails
        let junkDomains = settings.normalizedJunkDomains
        let junkKeywords = settings.normalizedJunkSubjectKeywords

        var priority: [MailInboxMessage] = []
        var likelyJunk: [MailInboxMessage] = []
        var other: [MailInboxMessage] = []

        for raw in rawMessages {
            let email = normalizedSenderEmail(from: raw.sender)
            let senderName = normalizedSenderName(from: raw.sender, fallbackEmail: email)
            let senderDomain = email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
            let subject = raw.subject.isEmpty ? "(No subject)" : raw.subject

            var priorityReason: String?
            if !email.isEmpty, customerEmailSet.contains(email) {
                priorityReason = "Customer email"
            } else if !email.isEmpty, vipEmails.contains(email) {
                priorityReason = "VIP sender"
            } else if !senderDomain.isEmpty, vipDomains.contains(senderDomain) {
                priorityReason = "VIP domain"
            }

            let junkAssessment = settings.scanLikelyJunk
                ? likelyJunkAssessment(
                    senderName: senderName,
                    senderEmail: email,
                    senderDomain: senderDomain,
                    subject: subject,
                    junkEmails: junkEmails,
                    junkDomains: junkDomains,
                    junkKeywords: junkKeywords
                )
                : nil

            let message = MailInboxMessage(
                id: raw.id,
                provider: provider,
                senderName: senderName,
                senderEmail: email,
                subject: subject,
                mailbox: raw.mailbox,
                receivedAtText: raw.receivedAtText,
                receivedAt: raw.receivedAt,
                isPriority: priorityReason != nil,
                priorityReason: priorityReason,
                isLikelyJunk: junkAssessment != nil,
                isStrongLikelyJunk: junkAssessment?.isStrong ?? false,
                junkReason: junkAssessment?.reason,
                supportsDirectActions: context.supportsDirectActions
            )

            if priorityReason != nil {
                priority.append(message)
            } else if junkAssessment != nil {
                likelyJunk.append(message)
            } else {
                other.append(message)
            }
        }

        return MailInboxSnapshot(
            priorityMessages: priority,
            likelyJunkMessages: likelyJunk,
            otherMessages: other,
            scannedAt: Date(),
            diagnosticMessage: context.diagnosticMessage
        )
    }

    private static func fetchUnreadMessagesWithFallback(settings: MailReviewSettings) throws -> MailFetchContext {
        let preferredProvider = resolvedProvider(for: settings)
        do {
            return MailFetchContext(
                provider: preferredProvider,
                rawMessages: try fetchUnreadMessages(using: preferredProvider),
                supportsDirectActions: true,
                diagnosticMessage: nil
            )
        } catch {
            var appleMailIndexError: Error?
            if preferredProvider == .appleMail {
                do {
                    return try fetchUnreadMessagesFromAppleMailIndex()
                } catch {
                    appleMailIndexError = error
                }
            }
            guard settings.preferredProvider == .automatic else {
                throw appleMailIndexError ?? error
            }
            let fallbackProvider: MailProviderKind = preferredProvider == .appleMail ? .outlook : .appleMail
            do {
                return MailFetchContext(
                    provider: fallbackProvider,
                    rawMessages: try fetchUnreadMessages(using: fallbackProvider),
                    supportsDirectActions: true,
                    diagnosticMessage: nil
                )
            } catch let fallbackError {
                if fallbackProvider == .appleMail {
                    do {
                        return try fetchUnreadMessagesFromAppleMailIndex()
                    } catch {
                        throw error
                    }
                }
                throw fallbackError
            }
        }
    }

    static func openPreferredMailApp(using settings: MailReviewSettings) throws {
        let provider = resolvedProvider(for: settings)
        let bundleIdentifier: String
        switch provider {
        case .outlook:
            bundleIdentifier = "com.microsoft.Outlook"
        case .automatic, .appleMail:
            bundleIdentifier = "com.apple.mail"
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw MailReviewServiceError.automationFailed("Could not find \(provider.title) on this Mac.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    static func openMessage(_ message: MailInboxMessage) throws {
        guard message.supportsDirectActions else {
            try openPreferredMailApp(using: MailReviewSettings.load())
            return
        }
        switch message.provider {
        case .outlook:
            _ = try runAppleScript(outlookOpenScript(messageID: message.id), appName: "Outlook")
        case .automatic, .appleMail:
            _ = try runAppleScript(appleMailOpenScript(messageID: message.id), appName: "Mail")
        }
    }

    static func markMessageRead(_ message: MailInboxMessage) throws {
        guard message.supportsDirectActions else {
            throw MailReviewServiceError.automationFailed("Mail Center is reading Apple Mail in read-only fallback mode right now. Open Mail to mark this message as read directly.")
        }
        switch message.provider {
        case .outlook:
            _ = try runAppleScript(outlookMarkReadScript(messageID: message.id), appName: "Outlook")
        case .automatic, .appleMail:
            _ = try runAppleScript(appleMailMarkReadScript(messageID: message.id), appName: "Mail")
        }
    }

    static func trashMessage(_ message: MailInboxMessage) throws {
        guard message.supportsDirectActions else {
            throw MailReviewServiceError.automationFailed("Mail Center is reading Apple Mail in read-only fallback mode right now. Open Mail to clear this message there.")
        }
        switch message.provider {
        case .outlook:
            _ = try runAppleScript(outlookTrashScript(messageID: message.id), appName: "Outlook")
        case .automatic, .appleMail:
            _ = try runAppleScript(appleMailTrashScript(messageID: message.id), appName: "Mail")
        }
    }

    static func clearJunkFolder(using settings: MailReviewSettings) throws -> Int {
        try clearJunkFolderIfNeeded(using: resolvedProvider(for: settings))
    }

    static func markAllUnreadMessagesRead(using settings: MailReviewSettings) throws -> Int {
        let provider = resolvedProvider(for: settings)
        let output: String
        switch provider {
        case .outlook:
            output = try runAppleScript(outlookMarkAllUnreadReadScript(), appName: "Outlook")
        case .automatic, .appleMail:
            output = try runAppleScript(appleMailMarkAllUnreadReadScript(), appName: "Mail")
        }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func searchMailHistory(
        using settings: MailReviewSettings,
        keyword: String,
        since cutoffDate: Date?,
        limit: Int = 40
    ) throws -> [MailHistoryMessage] {
        let provider = resolvedProvider(for: settings)
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return [] }

        let rawMessages: [RawMailHistoryMessage]
        switch provider {
        case .outlook:
            throw MailReviewServiceError.automationFailed("Mail search is currently available for Apple Mail on this Mac.")
        case .automatic, .appleMail:
            rawMessages = try fetchAppleMailHistory(keyword: trimmedKeyword, since: cutoffDate, limit: limit)
        }

        return rawMessages.map {
            let email = normalizedSenderEmail(from: $0.participantDisplay)
            let participant = normalizedSenderName(from: $0.participantDisplay, fallbackEmail: email)
            return MailHistoryMessage(
                id: $0.id,
                provider: provider,
                direction: $0.direction,
                accountName: $0.accountName,
                mailbox: $0.mailbox,
                participantDisplay: participant,
                participantEmail: email,
                subject: $0.subject.isEmpty ? "(No subject)" : $0.subject,
                dateText: $0.dateText,
                date: $0.date
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?):
                if left != right { return left > right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return lhs.id > rhs.id
        }
    }

    static func fetchRecentSentMessages(
        using settings: MailReviewSettings,
        since cutoffDate: Date?,
        limit: Int = 40
    ) throws -> [MailHistoryMessage] {
        let provider = resolvedProvider(for: settings)
        let rawMessages: [RawMailHistoryMessage]
        switch provider {
        case .outlook:
            throw MailReviewServiceError.automationFailed("Recent sent mail is currently available for Apple Mail on this Mac.")
        case .automatic, .appleMail:
            rawMessages = try fetchAppleMailRecentSent(since: cutoffDate, limit: limit)
        }

        return rawMessages.map {
            let email = normalizedSenderEmail(from: $0.participantDisplay)
            let participant = normalizedSenderName(from: $0.participantDisplay, fallbackEmail: email)
            return MailHistoryMessage(
                id: $0.id,
                provider: provider,
                direction: $0.direction,
                accountName: $0.accountName,
                mailbox: $0.mailbox,
                participantDisplay: participant,
                participantEmail: email,
                subject: $0.subject.isEmpty ? "(No subject)" : $0.subject,
                dateText: $0.dateText,
                date: $0.date
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?):
                if left != right { return left > right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return lhs.id > rhs.id
        }
    }

    static func fetchBodyText(for message: MailInboxMessage) throws -> String {
        let output: String
        switch message.provider {
        case .outlook:
            throw MailReviewServiceError.automationFailed("Inline body previews are currently available for Apple Mail on this Mac.")
        case .automatic, .appleMail:
            output = try runAppleScript(appleMailFetchInboxBodyScript(messageID: message.id), appName: "Mail")
        }
        return normalizedMailBody(output)
    }

    static func fetchBodyText(for message: MailHistoryMessage) throws -> String {
        let output: String
        switch message.provider {
        case .outlook:
            throw MailReviewServiceError.automationFailed("Inline body previews are currently available for Apple Mail on this Mac.")
        case .automatic, .appleMail:
            switch message.direction {
            case .inbox:
                output = try runAppleScript(appleMailFetchInboxBodyScript(messageID: message.id), appName: "Mail")
            case .sent:
                output = try runAppleScript(
                    appleMailFetchSentBodyScript(
                        messageID: message.id,
                        accountName: message.accountName,
                        mailboxName: message.mailbox
                    ),
                    appName: "Mail"
                )
            }
        }
        return normalizedMailBody(output)
    }

    static func openHistoryMessage(_ message: MailHistoryMessage) throws {
        switch message.provider {
        case .outlook:
            throw MailReviewServiceError.automationFailed("Opening search results is currently available for Apple Mail on this Mac.")
        case .automatic, .appleMail:
            let script: String
            switch message.direction {
            case .inbox:
                script = appleMailOpenScript(messageID: message.id)
            case .sent:
                script = appleMailOpenSentHistoryScript(messageID: message.id, accountName: message.accountName, mailboxName: message.mailbox)
            }
            _ = try runAppleScript(script, appName: "Mail")
        }
    }

    private struct RawMailMessage {
        let id: Int64
        let sender: String
        let subject: String
        let mailbox: String
        let receivedAtText: String
        let receivedAt: Date?
    }

    private struct RawMailHistoryMessage {
        let id: Int64
        let direction: MailHistoryDirection
        let accountName: String
        let mailbox: String
        let participantDisplay: String
        let subject: String
        let dateText: String
        let date: Date?
    }

    private static func fetchUnreadMessagesFromAppleMailIndex() throws -> MailFetchContext {
        let candidatePaths = candidateAppleMailEnvelopeIndexPaths()

        for path in candidatePaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                let rows = try fetchUnreadMessagesFromEnvelopeIndex(at: path)
                return MailFetchContext(
                    provider: .appleMail,
                    rawMessages: rows,
                    supportsDirectActions: false,
                    diagnosticMessage: "Apple Mail did not respond to live automation on this Mac, so Mail Center is showing unread mail from Mail's local index. Use Open Mail for direct cleanup actions."
                )
            } catch {
                continue
            }
        }

        throw MailReviewServiceError.localIndexUnavailable(
            "Apple Mail is installed, but its live automation timed out and the local Mail index was not accessible. Open Mail once, then grant Renaissance Filed Full Disk Access in System Settings > Privacy & Security if you want Mail Center to read Apple Mail reliably."
        )
    }

    private static func fetchUnreadMessages(using provider: MailProviderKind) throws -> [RawMailMessage] {
        let output: String
        switch provider {
        case .outlook:
            output = try runAppleScript(outlookFetchUnreadScript(), appName: "Outlook")
        case .automatic, .appleMail:
            output = try runAppleScript(appleMailFetchUnreadScript(), appName: "Mail")
        }
        guard !output.isEmpty else { return [] }

        return output
            .split(separator: recordSeparator)
            .compactMap { record -> RawMailMessage? in
                let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 5, let id = Int64(fields[0]) else { return nil }
                return RawMailMessage(
                    id: id,
                    sender: fields[1],
                    subject: fields[2],
                    mailbox: fields[3],
                    receivedAtText: fields[4],
                    receivedAt: parseReceivedDate(fields[4])
                )
            }
    }

    private static func fetchAppleMailHistory(
        keyword: String,
        since cutoffDate: Date?,
        limit: Int
    ) throws -> [RawMailHistoryMessage] {
        let output = try runAppleScript(
            appleMailSearchHistoryScriptV2(
                keyword: keyword,
                daysBack: daysBack(from: cutoffDate),
                limit: limit
            ),
            appName: "Mail"
        )
        return parseRawMailHistoryMessages(output)
    }

    private static func fetchAppleMailRecentSent(
        since cutoffDate: Date?,
        limit: Int
    ) throws -> [RawMailHistoryMessage] {
        let output = try runAppleScript(
            appleMailRecentSentScriptV2(
                daysBack: daysBack(from: cutoffDate),
                limit: limit
            ),
            appName: "Mail"
        )
        return parseRawMailHistoryMessages(output)
    }

    private static func parseRawMailHistoryMessages(_ output: String) -> [RawMailHistoryMessage] {
        guard !output.isEmpty else { return [] }
        return output
            .split(separator: recordSeparator)
            .compactMap { record in
                let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 7, let id = Int64(fields[0]) else { return nil }
                let direction = MailHistoryDirection(rawValue: fields[1].lowercased()) ?? .inbox
                return RawMailHistoryMessage(
                    id: id,
                    direction: direction,
                    accountName: fields[2],
                    mailbox: fields[3],
                    participantDisplay: fields[4],
                    subject: fields[5],
                    dateText: fields[6],
                    date: parseReceivedDate(fields[6])
                )
            }
    }

    private static func candidateAppleMailEnvelopeIndexPaths() -> [String] {
        let home = NSHomeDirectory()
        let roots = [
            "\(home)/Library/Mail",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail"
        ]
        var candidates: [String] = []
        let fileManager = FileManager.default

        for root in roots {
            if let entries = try? fileManager.contentsOfDirectory(atPath: root) {
                for entry in entries.sorted(by: >) where entry.hasPrefix("V") {
                    candidates.append("\(root)/\(entry)/MailData/Envelope Index")
                }
            }

            for version in stride(from: 20, through: 1, by: -1) {
                candidates.append("\(root)/V\(version)/MailData/Envelope Index")
            }
            candidates.append("\(root)/MailData/Envelope Index")
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func fetchUnreadMessagesFromEnvelopeIndex(at path: String) throws -> [RawMailMessage] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Could not open Apple Mail index."
            sqlite3_close(db)
            throw MailReviewServiceError.localIndexUnavailable(message)
        }
        defer { sqlite3_close(db) }

        let messageColumns = try tableColumns(named: "messages", db: db)
        guard !messageColumns.isEmpty else {
            throw MailReviewServiceError.localIndexUnavailable("Apple Mail index does not expose a readable messages table.")
        }

        let readExpression: String
        if messageColumns.contains("read") {
            readExpression = "COALESCE(messages.read, 0)"
        } else {
            throw MailReviewServiceError.localIndexUnavailable("Apple Mail index schema on this Mac does not expose a readable unread flag.")
        }

        let tables = try existingTables(db: db)
        let subjectExpression: String
        var joins: [String] = []

        if tables.contains("subjects"), messageColumns.contains("subject"),
           (try tableColumns(named: "subjects", db: db)).contains("subject") {
            joins.append("LEFT JOIN subjects ON messages.subject = subjects.ROWID")
            subjectExpression = "COALESCE(subjects.subject, '')"
        } else if messageColumns.contains("subject") {
            subjectExpression = "COALESCE(CAST(messages.subject AS TEXT), '')"
        } else {
            subjectExpression = "''"
        }

        let senderExpression: String
        if tables.contains("addresses"), messageColumns.contains("sender") {
            let addressColumns = try tableColumns(named: "addresses", db: db)
            if addressColumns.contains("address") || addressColumns.contains("comment") {
                joins.append("LEFT JOIN addresses sender ON messages.sender = sender.ROWID")
                let commentExpr = addressColumns.contains("comment") ? "COALESCE(sender.comment, '')" : "''"
                let addressExpr = addressColumns.contains("address") ? "COALESCE(sender.address, '')" : "''"
                senderExpression = """
                CASE
                    WHEN \(commentExpr) != '' AND \(addressExpr) != '' THEN \(commentExpr) || ' <' || \(addressExpr) || '>'
                    WHEN \(commentExpr) != '' THEN \(commentExpr)
                    ELSE \(addressExpr)
                END
                """
            } else {
                senderExpression = messageColumns.contains("sender") ? "COALESCE(CAST(messages.sender AS TEXT), '')" : "''"
            }
        } else {
            senderExpression = messageColumns.contains("sender") ? "COALESCE(CAST(messages.sender AS TEXT), '')" : "''"
        }

        let mailboxExpression: String
        if tables.contains("mailboxes"), messageColumns.contains("mailbox") {
            let mailboxColumns = try tableColumns(named: "mailboxes", db: db)
            if mailboxColumns.contains("url") {
                joins.append("LEFT JOIN mailboxes ON messages.mailbox = mailboxes.ROWID")
                mailboxExpression = "COALESCE(mailboxes.url, CAST(messages.mailbox AS TEXT), '')"
            } else {
                mailboxExpression = "COALESCE(CAST(messages.mailbox AS TEXT), '')"
            }
        } else {
            mailboxExpression = "COALESCE(CAST(messages.mailbox AS TEXT), '')"
        }

        let dateExpression: String
        if messageColumns.contains("date_received") {
            dateExpression = "COALESCE(messages.date_received, 0)"
        } else if messageColumns.contains("display_date") {
            dateExpression = "COALESCE(messages.display_date, 0)"
        } else if messageColumns.contains("date_sent") {
            dateExpression = "COALESCE(messages.date_sent, 0)"
        } else {
            dateExpression = "0"
        }

        let sql = """
        SELECT
            messages.ROWID,
            \(senderExpression) AS sender_text,
            \(subjectExpression) AS subject_text,
            \(mailboxExpression) AS mailbox_text,
            \(dateExpression) AS received_value
        FROM messages
        \(joins.joined(separator: "\n"))
        WHERE \(readExpression) = 0
        ORDER BY \(dateExpression) DESC
        LIMIT \(maxIndexedMessages);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Could not query Apple Mail index."
            throw MailReviewServiceError.localIndexUnavailable(message)
        }
        defer { sqlite3_finalize(statement) }

        var messages: [RawMailMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let sender = sqliteColumnText(statement, index: 1)
            let subject = sqliteColumnText(statement, index: 2)
            let mailbox = mailboxDisplayName(from: sqliteColumnText(statement, index: 3))
            let receivedRawValue = sqlite3_column_double(statement, 4)
            let receivedAtText = receivedDisplayText(from: receivedRawValue)
            messages.append(
                RawMailMessage(
                    id: id,
                    sender: sender,
                    subject: subject,
                    mailbox: mailbox,
                    receivedAtText: receivedAtText,
                    receivedAt: receivedRawValue > 0
                        ? Date(timeIntervalSince1970: receivedRawValue > 10_000_000_000 ? receivedRawValue / 1_000_000_000 : receivedRawValue)
                        : nil
                )
            )
        }

        return messages
    }

    private static func appleMailFetchUnreadScript() -> String {
        """
        set fieldSep to character id 31
        set recordSep to character id 30
        set maxMessages to \(maxLiveAppleMailMessages)

        on replaceText(findText, replacementText, sourceText)
            set AppleScript's text item delimiters to findText
            set sourceItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set updatedText to sourceItems as text
            set AppleScript's text item delimiters to ""
            return updatedText
        end replaceText

        on sanitizeText(sourceText)
            set cleanedText to sourceText as text
            set cleanedText to my replaceText(return, " ", cleanedText)
            set cleanedText to my replaceText(linefeed, " ", cleanedText)
            set cleanedText to my replaceText(tab, " ", cleanedText)
            set cleanedText to my replaceText((character id 31), " ", cleanedText)
            set cleanedText to my replaceText((character id 30), " ", cleanedText)
            return cleanedText
        end sanitizeText

        tell application "Mail"
            set unreadTotal to unread count of inbox
            if unreadTotal is 0 then return ""
            set sampleCount to unreadTotal
            if sampleCount > maxMessages then set sampleCount to maxMessages
            set unreadMessages to (messages 1 thru sampleCount of inbox whose read status is false)
            set outputLines to {}
            repeat with messageRef in unreadMessages
                set lineParts to {¬
                    (id of messageRef as string), ¬
                    my sanitizeText(sender of messageRef as string), ¬
                    my sanitizeText(subject of messageRef as string), ¬
                    my sanitizeText(name of mailbox of messageRef as string), ¬
                    my sanitizeText(date received of messageRef as string)}
                set AppleScript's text item delimiters to fieldSep
                set end of outputLines to (lineParts as text)
                set AppleScript's text item delimiters to ""
            end repeat
        end tell

        set AppleScript's text item delimiters to recordSep
        set outputText to outputLines as text
        set AppleScript's text item delimiters to ""
        return outputText
        """
    }

    private static func appleMailSearchHistoryScript(keyword: String, daysBack: Int?, limit: Int) -> String {
        let escapedKeyword = appleScriptStringLiteral(keyword)
        let daysClause = daysBack.map { "set cutoffDate to (current date) - (\($0) * days)" } ?? "set cutoffDate to missing value"
        let inboxDateCondition = daysBack != nil ? "and (date received of messageRef) > cutoffDate" : ""
        let sentDateCondition = daysBack != nil ? "and (date sent of messageRef) > cutoffDate" : ""
        return """
        set fieldSep to character id 31
        set recordSep to character id 30
        set maxMessages to \(max(1, limit))
        set keywordText to \(escapedKeyword)
        \(daysClause)

        on replaceText(findText, replacementText, sourceText)
            set AppleScript's text item delimiters to findText
            set sourceItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set updatedText to sourceItems as text
            set AppleScript's text item delimiters to ""
            return updatedText
        end replaceText

        on sanitizeText(sourceText)
            set cleanedText to sourceText as text
            set cleanedText to my replaceText(return, " ", cleanedText)
            set cleanedText to my replaceText(linefeed, " ", cleanedText)
            set cleanedText to my replaceText(tab, " ", cleanedText)
            set cleanedText to my replaceText((character id 31), " ", cleanedText)
            set cleanedText to my replaceText((character id 30), " ", cleanedText)
            return cleanedText
        end sanitizeText

        on matchesKeyword(subjectText, participantText, keywordText)
            if keywordText is "" then return true
            ignoring case
                if subjectText contains keywordText then return true
                if participantText contains keywordText then return true
            end ignoring
            return false
        end matchesKeyword

        tell application "Mail"
            set outputLines to {}
            set collectedCount to 0

            set inboxMessages to messages of inbox
            repeat with messageRef in inboxMessages
                if collectedCount ≥ maxMessages then exit repeat
                try
                    if true \(inboxDateCondition) then
                        set senderText to my sanitizeText(sender of messageRef as string)
                        set subjectText to my sanitizeText(subject of messageRef as string)
                        if my matchesKeyword(subjectText, senderText, keywordText) then
                            set lineParts to {(id of messageRef as string), "inbox", "", my sanitizeText(name of mailbox of messageRef as string), senderText, subjectText, my sanitizeText(date received of messageRef as string)}
                            set AppleScript's text item delimiters to fieldSep
                            set end of outputLines to (lineParts as text)
                            set AppleScript's text item delimiters to ""
                            set collectedCount to collectedCount + 1
                        end if
                    end if
                end try
            end repeat

            if collectedCount < maxMessages then
                repeat with acct in every account
                    try
                        set acctName to name of acct as string
                        set sentBoxes to (every mailbox of acct whose name contains "Sent" or name contains "sent")
                        repeat with sentBox in sentBoxes
                            if collectedCount ≥ maxMessages then exit repeat
                            set sentMessages to messages of sentBox
                            repeat with messageRef in sentMessages
                                if collectedCount ≥ maxMessages then exit repeat
                                try
                                    if true \(sentDateCondition) then
                                        set recipientText to ""
                                        try
                                            set recipientText to address of first to recipient of messageRef as string
                                        end try
                                        set recipientText to my sanitizeText(recipientText)
                                        set subjectText to my sanitizeText(subject of messageRef as string)
                                        if my matchesKeyword(subjectText, recipientText, keywordText) then
                                            set lineParts to {(id of messageRef as string), "sent", my sanitizeText(acctName), my sanitizeText(name of sentBox as string), recipientText, subjectText, my sanitizeText(date sent of messageRef as string)}
                                            set AppleScript's text item delimiters to fieldSep
                                            set end of outputLines to (lineParts as text)
                                            set AppleScript's text item delimiters to ""
                                            set collectedCount to collectedCount + 1
                                        end if
                                    end if
                                end try
                            end repeat
                        end repeat
                    end try
                    if collectedCount ≥ maxMessages then exit repeat
                end repeat
            end if
        end tell

        set AppleScript's text item delimiters to recordSep
        set outputText to outputLines as text
        set AppleScript's text item delimiters to ""
        return outputText
        """
    }

    private static func appleMailRecentSentScript(daysBack: Int?, limit: Int) -> String {
        let daysClause = daysBack.map { "set cutoffDate to (current date) - (\($0) * days)" } ?? "set cutoffDate to missing value"
        let sentDateCondition = daysBack != nil ? "and (date sent of messageRef) > cutoffDate" : ""
        return """
        set fieldSep to character id 31
        set recordSep to character id 30
        set maxMessages to \(max(1, limit))
        \(daysClause)

        on replaceText(findText, replacementText, sourceText)
            set AppleScript's text item delimiters to findText
            set sourceItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set updatedText to sourceItems as text
            set AppleScript's text item delimiters to ""
            return updatedText
        end replaceText

        on sanitizeText(sourceText)
            set cleanedText to sourceText as text
            set cleanedText to my replaceText(return, " ", cleanedText)
            set cleanedText to my replaceText(linefeed, " ", cleanedText)
            set cleanedText to my replaceText(tab, " ", cleanedText)
            set cleanedText to my replaceText((character id 31), " ", cleanedText)
            set cleanedText to my replaceText((character id 30), " ", cleanedText)
            return cleanedText
        end sanitizeText

        tell application "Mail"
            set outputLines to {}
            set collectedCount to 0
            repeat with acct in every account
                try
                    set acctName to name of acct as string
                    set sentBoxes to (every mailbox of acct whose name contains "Sent" or name contains "sent")
                    repeat with sentBox in sentBoxes
                        if collectedCount ≥ maxMessages then exit repeat
                        set sentMessages to messages of sentBox
                        repeat with messageRef in sentMessages
                            if collectedCount ≥ maxMessages then exit repeat
                            try
                                if true \(sentDateCondition) then
                                    set recipientText to ""
                                    try
                                        set recipientText to address of first to recipient of messageRef as string
                                    end try
                                    set recipientText to my sanitizeText(recipientText)
                                    set lineParts to {(id of messageRef as string), "sent", my sanitizeText(acctName), my sanitizeText(name of sentBox as string), recipientText, my sanitizeText(subject of messageRef as string), my sanitizeText(date sent of messageRef as string)}
                                    set AppleScript's text item delimiters to fieldSep
                                    set end of outputLines to (lineParts as text)
                                    set AppleScript's text item delimiters to ""
                                    set collectedCount to collectedCount + 1
                                end if
                            end try
                        end repeat
                    end repeat
                end try
                if collectedCount ≥ maxMessages then exit repeat
            end repeat
        end tell

        set AppleScript's text item delimiters to recordSep
        set outputText to outputLines as text
        set AppleScript's text item delimiters to ""
        return outputText
        """
    }

    private static func outlookFetchUnreadScript() -> String {
        """
        set fieldSep to character id 31
        set recordSep to character id 30

        on replaceText(findText, replacementText, sourceText)
            set AppleScript's text item delimiters to findText
            set sourceItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set updatedText to sourceItems as text
            set AppleScript's text item delimiters to ""
            return updatedText
        end replaceText

        on sanitizeText(sourceText)
            set cleanedText to sourceText as text
            set cleanedText to my replaceText(return, " ", cleanedText)
            set cleanedText to my replaceText(linefeed, " ", cleanedText)
            set cleanedText to my replaceText(tab, " ", cleanedText)
            set cleanedText to my replaceText((character id 31), " ", cleanedText)
            set cleanedText to my replaceText((character id 30), " ", cleanedText)
            return cleanedText
        end sanitizeText

        tell application "Microsoft Outlook"
            set unreadMessages to (every incoming message of inbox whose is read is false)
            set outputLines to {}
            repeat with messageRef in unreadMessages
                set senderName to ""
                set senderAddress to ""
                try
                    set senderName to name of sender of messageRef as string
                end try
                try
                    set senderAddress to address of sender of messageRef as string
                end try
                set combinedSender to my sanitizeText(senderName)
                if senderAddress is not "" then
                    if combinedSender is not "" then
                        set combinedSender to combinedSender & " <" & my sanitizeText(senderAddress) & ">"
                    else
                        set combinedSender to my sanitizeText(senderAddress)
                    end if
                end if
                set lineParts to {¬
                    (id of messageRef as string), ¬
                    combinedSender, ¬
                    my sanitizeText(subject of messageRef as string), ¬
                    my sanitizeText(name of folder of messageRef as string), ¬
                    my sanitizeText(time received of messageRef as string)}
                set AppleScript's text item delimiters to fieldSep
                set end of outputLines to (lineParts as text)
                set AppleScript's text item delimiters to ""
            end repeat
        end tell

        set AppleScript's text item delimiters to recordSep
        set outputText to outputLines as text
        set AppleScript's text item delimiters to ""
        return outputText
        """
    }

    private static func resolvedProvider(for settings: MailReviewSettings) -> MailProviderKind {
        switch settings.preferredProvider {
        case .automatic:
            return isAppleMailAvailable() ? .appleMail : (isOutlookAvailable() ? .outlook : .appleMail)
        case .outlook:
            return isOutlookAvailable() ? .outlook : .appleMail
        case .appleMail:
            return .appleMail
        }
    }

    private static func isAppleMailAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") != nil
    }

    private static func isOutlookAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil
    }

    private static func normalizedSenderEmail(from sender: String) -> String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) {
            return String(trimmed[match]).lowercased()
        }
        return trimmed.contains("@") ? trimmed.lowercased() : ""
    }

    private static func normalizedSenderName(from sender: String, fallbackEmail: String) -> String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let emailRange = trimmed.range(of: #"\s*<[^>]+>\s*$"#, options: .regularExpression) {
            let name = String(trimmed[..<emailRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? fallbackEmail : name
        }
        if !fallbackEmail.isEmpty, trimmed.caseInsensitiveCompare(fallbackEmail) == .orderedSame {
            return fallbackEmail
        }
        return trimmed.isEmpty ? fallbackEmail : trimmed
    }

    private static func runAppleScript(_ script: String, appName: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw MailReviewServiceError.automationFailed("\(appName) automation could not start: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(automationTimeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw MailReviewServiceError.automationTimedOut("\(appName) did not respond in time. Open \(appName) and try again, or review messages directly in Mail if Mail Center is using read-only fallback mode.")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if errorText.localizedCaseInsensitiveContains("Message not found") {
                throw MailReviewServiceError.messageNotFound
            }
            let message = errorText.isEmpty ? "\(appName) automation failed." : errorText
            throw MailReviewServiceError.automationFailed(message)
        }

        return output
    }

    private static func clearJunkFolderIfNeeded(using provider: MailProviderKind) throws -> Int {
        switch provider {
        case .outlook:
            let output = try runAppleScript(outlookClearJunkFolderScript(), appName: "Outlook")
            return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        case .automatic, .appleMail:
            let output = try runAppleScript(appleMailClearJunkFolderScript(), appName: "Mail")
            return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
    }

    private static func appleMailOpenScript(messageID: Int64) -> String {
        """
        tell application "Mail"
            set targetMessages to (every message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set targetMessage to item 1 of targetMessages
            activate
            try
                if (count of message viewers) is 0 then make new message viewer
                set selected messages of message viewer 1 to {targetMessage}
            end try
            open targetMessage
        end tell
        """
    }

    private static func appleMailFetchInboxBodyScript(messageID: Int64) -> String {
        """
        tell application "Mail"
            set targetMessages to (every message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set targetMessage to item 1 of targetMessages
            try
                return content of targetMessage as string
            on error
                return source of targetMessage as string
            end try
        end tell
        """
    }

    private static func appleMailFetchSentBodyScript(messageID: Int64, accountName: String, mailboxName: String) -> String {
        """
        tell application "Mail"
            set targetAccounts to (every account whose name is \(appleScriptStringLiteral(accountName)))
            if (count of targetAccounts) is 0 then error "Message not found."
            set targetAccount to item 1 of targetAccounts
            set targetMailboxes to (every mailbox of targetAccount whose name is \(appleScriptStringLiteral(mailboxName)))
            if (count of targetMailboxes) is 0 then error "Message not found."
            set targetMailbox to item 1 of targetMailboxes
            set targetMessages to (every message of targetMailbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set targetMessage to item 1 of targetMessages
            try
                return content of targetMessage as string
            on error
                return source of targetMessage as string
            end try
        end tell
        """
    }

    private static func appleMailMarkReadScript(messageID: Int64) -> String {
        """
        tell application "Mail"
            set targetMessages to (every message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set read status of item 1 of targetMessages to true
        end tell
        """
    }

    private static func appleMailMarkAllUnreadReadScript() -> String {
        """
        tell application "Mail"
            set unreadMessages to (every message of inbox whose read status is false)
            set updatedCount to count of unreadMessages
            repeat with messageRef in unreadMessages
                set read status of messageRef to true
            end repeat
            return updatedCount as string
        end tell
        """
    }

    private static func appleMailTrashScript(messageID: Int64) -> String {
        """
        tell application "Mail"
            set targetMessages to (every message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            delete item 1 of targetMessages
        end tell
        """
    }

    private static func appleMailClearJunkFolderScript() -> String {
        """
        on isJunkName(mbName)
            if (mbName contains "Junk") or (mbName contains "junk") then return true
            if (mbName contains "Spam") or (mbName contains "spam") then return true
            if (mbName contains "Bulk") or (mbName contains "bulk") then return true
            return false
        end isJunkName

        tell application "Mail"
            set deletedCount to 0

            -- Account-nested junk folders (IMAP: iCloud "Junk", AOL/Verizon "Bulk", etc.)
            repeat with acct in (every account)
                try
                    repeat with mailboxRef in (every mailbox of acct)
                        try
                            if my isJunkName(name of mailboxRef as string) then
                                set junkMessages to every message of mailboxRef
                                set deletedCount to deletedCount + (count of junkMessages)
                                repeat with messageRef in reverse of junkMessages
                                    delete messageRef
                                end repeat
                            end if
                        end try
                    end repeat
                end try
            end repeat

            -- Top-level / On My Mac junk folders (not nested under an account)
            try
                repeat with mailboxRef in (every mailbox)
                    try
                        if my isJunkName(name of mailboxRef as string) then
                            set junkMessages to every message of mailboxRef
                            set deletedCount to deletedCount + (count of junkMessages)
                            repeat with messageRef in reverse of junkMessages
                                delete messageRef
                            end repeat
                        end if
                    end try
                end repeat
            end try

            return deletedCount as string
        end tell
        """
    }

    private static func appleMailSearchHistoryScriptV2(keyword: String, daysBack: Int?, limit: Int) -> String {
        let escapedKeyword = appleScriptStringLiteral(keyword)
        let cutoffClause = daysBack.map { "set cutoffDate to (current date) - (\($0) * days)" } ?? "set cutoffDate to missing value"
        let inboxCutoffCheck = daysBack != nil ? "if (date received of messageRef) < cutoffDate then error number -128" : ""
        let sentCutoffCheck = daysBack != nil ? "if (date sent of messageRef) < cutoffDate then error number -128" : ""

        return """
        set fieldSep to character id 31
        set recordSep to character id 30
        set maxMessages to \(max(1, limit))
        set keywordText to \(escapedKeyword)
        \(cutoffClause)

        on replaceText(findText, replacementText, sourceText)
            set AppleScript's text item delimiters to findText
            set sourceItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set updatedText to sourceItems as text
            set AppleScript's text item delimiters to ""
            return updatedText
        end replaceText

        on sanitizeText(sourceText)
            set cleanedText to sourceText as text
            set cleanedText to my replaceText(return, " ", cleanedText)
            set cleanedText to my replaceText(linefeed, " ", cleanedText)
            set cleanedText to my replaceText(tab, " ", cleanedText)
            set cleanedText to my replaceText((character id 31), " ", cleanedText)
            set cleanedText to my replaceText((character id 30), " ", cleanedText)
            return cleanedText
        end sanitizeText

        on matchesKeyword(subjectText, participantText, bodyText, keywordText)
            if keywordText is "" then return true
            ignoring case
                if subjectText contains keywordText then return true
                if participantText contains keywordText then return true
                if bodyText contains keywordText then return true
            end ignoring
            return false
        end matchesKeyword

        tell application "Mail"
            set outputLines to {}
            set collectedCount to 0

            repeat with messageRef in (messages of inbox)
                if collectedCount >= maxMessages then exit repeat
                try
                    \(inboxCutoffCheck)
                    set senderText to my sanitizeText(sender of messageRef as string)
                    set subjectText to my sanitizeText(subject of messageRef as string)
                    set bodyText to ""
                    try
                        set bodyText to my sanitizeText(content of messageRef as string)
                    end try
                    if my matchesKeyword(subjectText, senderText, bodyText, keywordText) then
                        set lineParts to {(id of messageRef as string), "inbox", "", my sanitizeText(name of mailbox of messageRef as string), senderText, subjectText, my sanitizeText(date received of messageRef as string)}
                        set AppleScript's text item delimiters to fieldSep
                        set end of outputLines to (lineParts as text)
                        set AppleScript's text item delimiters to ""
                        set collectedCount to collectedCount + 1
                    end if
                end try
            end repeat

            if collectedCount < maxMessages then
                repeat with acct in every account
                    try
                        set acctName to name of acct as string
                        set sentBoxes to (every mailbox of acct whose name contains "Sent" or name contains "sent")
                        repeat with sentBox in sentBoxes
                            if collectedCount >= maxMessages then exit repeat
                            repeat with messageRef in (messages of sentBox)
                                if collectedCount >= maxMessages then exit repeat
                                try
                                    \(sentCutoffCheck)
                                    set recipientText to ""
                                    try
                                        set recipientText to address of first to recipient of messageRef as string
                                    end try
                                    set recipientText to my sanitizeText(recipientText)
                                    set subjectText to my sanitizeText(subject of messageRef as string)
                                    set bodyText to ""
                                    try
                                        set bodyText to my sanitizeText(content of messageRef as string)
                                    end try
                                    if my matchesKeyword(subjectText, recipientText, bodyText, keywordText) then
                                        set lineParts to {(id of messageRef as string), "sent", my sanitizeText(acctName), my sanitizeText(name of sentBox as string), recipientText, subjectText, my sanitizeText(date sent of messageRef as string)}
                                        set AppleScript's text item delimiters to fieldSep
                                        set end of outputLines to (lineParts as text)
                                        set AppleScript's text item delimiters to ""
                                        set collectedCount to collectedCount + 1
                                    end if
                                end try
                            end repeat
                        end repeat
                    end try
                    if collectedCount >= maxMessages then exit repeat
                end repeat
            end if
        end tell

        set AppleScript's text item delimiters to recordSep
        set outputText to outputLines as text
        set AppleScript's text item delimiters to ""
        return outputText
        """
    }

    private static func appleMailRecentSentScriptV2(daysBack: Int?, limit: Int) -> String {
        let cutoffClause = daysBack.map { "set cutoffDate to (current date) - (\($0) * days)" } ?? "set cutoffDate to missing value"
        let sentCutoffCheck = daysBack != nil ? "if (date sent of messageRef) < cutoffDate then error number -128" : ""

        return """
        set fieldSep to character id 31
        set recordSep to character id 30
        set maxMessages to \(max(1, limit))
        \(cutoffClause)

        on replaceText(findText, replacementText, sourceText)
            set AppleScript's text item delimiters to findText
            set sourceItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set updatedText to sourceItems as text
            set AppleScript's text item delimiters to ""
            return updatedText
        end replaceText

        on sanitizeText(sourceText)
            set cleanedText to sourceText as text
            set cleanedText to my replaceText(return, " ", cleanedText)
            set cleanedText to my replaceText(linefeed, " ", cleanedText)
            set cleanedText to my replaceText(tab, " ", cleanedText)
            set cleanedText to my replaceText((character id 31), " ", cleanedText)
            set cleanedText to my replaceText((character id 30), " ", cleanedText)
            return cleanedText
        end sanitizeText

        tell application "Mail"
            set outputLines to {}
            set collectedCount to 0
            repeat with acct in every account
                try
                    set acctName to name of acct as string
                    set sentBoxes to (every mailbox of acct whose name contains "Sent" or name contains "sent")
                    repeat with sentBox in sentBoxes
                        if collectedCount >= maxMessages then exit repeat
                        repeat with messageRef in (messages of sentBox)
                            if collectedCount >= maxMessages then exit repeat
                            try
                                \(sentCutoffCheck)
                                set recipientText to ""
                                try
                                    set recipientText to address of first to recipient of messageRef as string
                                end try
                                set recipientText to my sanitizeText(recipientText)
                                set lineParts to {(id of messageRef as string), "sent", my sanitizeText(acctName), my sanitizeText(name of sentBox as string), recipientText, my sanitizeText(subject of messageRef as string), my sanitizeText(date sent of messageRef as string)}
                                set AppleScript's text item delimiters to fieldSep
                                set end of outputLines to (lineParts as text)
                                set AppleScript's text item delimiters to ""
                                set collectedCount to collectedCount + 1
                            end try
                        end repeat
                    end repeat
                end try
                if collectedCount >= maxMessages then exit repeat
            end repeat
        end tell

        set AppleScript's text item delimiters to recordSep
        set outputText to outputLines as text
        set AppleScript's text item delimiters to ""
        return outputText
        """
    }

    private static func appleMailOpenSentHistoryScript(messageID: Int64, accountName: String, mailboxName: String) -> String {
        """
        tell application "Mail"
            set targetAccounts to (every account whose name is \(appleScriptStringLiteral(accountName)))
            if (count of targetAccounts) is 0 then error "Message not found."
            set targetAccount to item 1 of targetAccounts
            set targetMailboxes to (every mailbox of targetAccount whose name is \(appleScriptStringLiteral(mailboxName)))
            if (count of targetMailboxes) is 0 then error "Message not found."
            set targetMailbox to item 1 of targetMailboxes
            set targetMessages to (every message of targetMailbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set targetMessage to item 1 of targetMessages
            activate
            try
                if (count of message viewers) is 0 then make new message viewer
                set selected messages of message viewer 1 to {targetMessage}
            end try
            open targetMessage
        end tell
        """
    }

    private static func outlookOpenScript(messageID: Int64) -> String {
        """
        tell application "Microsoft Outlook"
            set targetMessages to (every incoming message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set targetMessage to item 1 of targetMessages
            activate
            open targetMessage
        end tell
        """
    }

    private static func outlookMarkReadScript(messageID: Int64) -> String {
        """
        tell application "Microsoft Outlook"
            set targetMessages to (every incoming message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            set is read of item 1 of targetMessages to true
        end tell
        """
    }

    private static func outlookMarkAllUnreadReadScript() -> String {
        """
        tell application "Microsoft Outlook"
            set unreadMessages to (every incoming message of inbox whose is read is false)
            set updatedCount to count of unreadMessages
            repeat with messageRef in unreadMessages
                set is read of messageRef to true
            end repeat
            return updatedCount as string
        end tell
        """
    }

    private static func outlookTrashScript(messageID: Int64) -> String {
        """
        tell application "Microsoft Outlook"
            set targetMessages to (every incoming message of inbox whose id is \(messageID))
            if (count of targetMessages) is 0 then error "Message not found."
            delete item 1 of targetMessages
        end tell
        """
    }

    private static func outlookClearJunkFolderScript() -> String {
        """
        tell application "Microsoft Outlook"
            set junkMessages to every incoming message of junk mail
            set deletedCount to count of junkMessages
            repeat with messageRef in reverse of junkMessages
                delete messageRef
            end repeat
            return deletedCount as string
        end tell
        """
    }

    private static func likelyJunkAssessment(
        senderName: String,
        senderEmail: String,
        senderDomain: String,
        subject: String,
        junkEmails: Set<String>,
        junkDomains: Set<String>,
        junkKeywords: [String]
    ) -> JunkAssessment? {
        var reasons: [String] = []
        let loweredSubject = subject.lowercased()
        let loweredName = senderName.lowercased()
        let loweredEmail = senderEmail.lowercased()
        var isStrong = false

        if !senderEmail.isEmpty, junkEmails.contains(senderEmail) {
            reasons.append("junk sender")
            isStrong = true
        }
        if !senderDomain.isEmpty, junkDomains.contains(senderDomain) {
            reasons.append("junk domain")
            isStrong = true
        }
        let isNoReplySender =
            loweredEmail.contains("no-reply") ||
            loweredEmail.contains("noreply") ||
            loweredEmail.contains("do-not-reply")
        if isNoReplySender {
            reasons.append("no-reply sender")
        }
        let isMarketingName = loweredName.contains("marketing") || loweredName.contains("promo")
        if isMarketingName {
            reasons.append("marketing sender")
        }

        let matchedKeywords = junkKeywords.filter { keyword in
            !keyword.isEmpty && loweredSubject.contains(keyword)
        }
        if matchedKeywords.count >= 2 {
            reasons.append("multiple junk keywords")
        } else if let keyword = matchedKeywords.first, reasons.count >= 1 {
            reasons.append("keyword: \(keyword)")
        }

        if matchedKeywords.count >= 3 {
            isStrong = true
        }
        if isNoReplySender && matchedKeywords.count >= 1 {
            isStrong = true
        }
        if isMarketingName && matchedKeywords.count >= 2 {
            isStrong = true
        }
        if loweredSubject.contains("unsubscribe") && reasons.isEmpty {
            reasons.append("unsubscribe mail")
        } else if loweredSubject.contains("unsubscribe") && matchedKeywords.isEmpty {
            reasons.append("unsubscribe mail")
        }

        if loweredSubject.contains("opt out") && (isNoReplySender || isMarketingName) {
            isStrong = true
            if !reasons.contains("unsubscribe mail") {
                reasons.append("opt-out mail")
            }
        }

        guard !reasons.isEmpty else { return nil }
        return JunkAssessment(
            reason: reasons.prefix(2).joined(separator: " + "),
            isStrong: isStrong
        )
    }

    private static func normalizedRecipientEmails(from rawValue: String) -> [String] {
        rawValue
            .split { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func existingTables(db: OpaquePointer) throws -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Could not inspect Apple Mail index."
            throw MailReviewServiceError.localIndexUnavailable(message)
        }
        defer { sqlite3_finalize(statement) }

        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            names.insert(sqliteColumnText(statement, index: 0))
        }
        return names
    }

    private static func tableColumns(named table: String, db: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(sqliteColumnText(statement, index: 1))
        }
        return columns
    }

    private static func sqliteColumnText(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private static func mailboxDisplayName(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Inbox" }
        if let decoded = trimmed.removingPercentEncoding {
            let components = decoded
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            if let last = components.last {
                return last.replacingOccurrences(of: ".mbox", with: "")
            }
            return decoded
        }
        return trimmed
    }

    private static func receivedDisplayText(from rawValue: Double) -> String {
        guard rawValue > 0 else { return "" }
        let seconds: TimeInterval = rawValue > 10_000_000_000 ? rawValue / 1_000_000_000 : rawValue
        let date = Date(timeIntervalSince1970: seconds)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func parseReceivedDate(_ rawValue: String) -> Date? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let formats = [
            "EEEE, MMMM d, yyyy 'at' h:mm:ss a",
            "EEEE, MMMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy 'at' h:mm:ss a",
            "MMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy, h:mm:ss a",
            "MMM d, yyyy, h:mm a"
        ]

        for dateFormat in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = dateFormat
            if let parsed = formatter.date(from: normalized) {
                return parsed
            }
        }

        return nil
    }

    private static func daysBack(from cutoffDate: Date?) -> Int? {
        guard let cutoffDate else { return nil }
        let interval = Date().timeIntervalSince(cutoffDate)
        guard interval > 0 else { return 0 }
        return max(Int(ceil(interval / 86_400)), 0)
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func normalizedMailBody(_ body: String) -> String {
        body
            .replacingOccurrences(of: String(fieldSeparator), with: " ")
            .replacingOccurrences(of: String(recordSeparator), with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
