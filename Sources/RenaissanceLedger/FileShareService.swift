import AppKit
import Foundation

enum FileShareServiceError: LocalizedError {
    case fileMissing
    case emailUnavailable

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "The selected file could not be found."
        case .emailUnavailable:
            return "Mail could not be opened for this file."
        }
    }
}

@MainActor
enum FileShareService {
    static func emailFile(fileURL: URL, subject: String, recipientEmails: [String] = []) throws {
        try emailFiles(fileURLs: [fileURL], subject: subject, recipientEmails: recipientEmails)
    }

    static func emailFiles(fileURLs: [URL], subject: String, recipientEmails: [String] = []) throws {
        let attachments = fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !attachments.isEmpty else {
            throw FileShareServiceError.fileMissing
        }

        let cleanedRecipients = recipientEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if composeWithPreferredMailApp(fileURLs: attachments, subject: subject, recipientEmails: cleanedRecipients) {
            return
        }

        guard let service = NSSharingService(named: .composeEmail) else {
            throw FileShareServiceError.emailUnavailable
        }

        service.subject = subject
        service.recipients = cleanedRecipients
        service.perform(withItems: attachments)
    }

    static func normalizedRecipientEmails(from rawValue: String) -> [String] {
        rawValue
            .split { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func composeWithPreferredMailApp(fileURLs: [URL], subject: String, recipientEmails: [String]) -> Bool {
        switch preferredProvider() {
        case .automatic:
            return composeWithMailApp(fileURLs: fileURLs, subject: subject, recipientEmails: recipientEmails)
                || composeWithOutlookApp(fileURLs: fileURLs, subject: subject, recipientEmails: recipientEmails)
        case .outlook:
            return composeWithOutlookApp(fileURLs: fileURLs, subject: subject, recipientEmails: recipientEmails)
                || composeWithMailApp(fileURLs: fileURLs, subject: subject, recipientEmails: recipientEmails)
        case .appleMail:
            return composeWithMailApp(fileURLs: fileURLs, subject: subject, recipientEmails: recipientEmails)
        }
    }

    private static func preferredProvider() -> MailProviderKind {
        MailProviderKind(rawValue: UserDefaults.standard.string(forKey: "mailReview.preferredProvider") ?? "") ?? .appleMail
    }

    private static func composeWithOutlookApp(fileURLs: [URL], subject: String, recipientEmails: [String]) -> Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil else {
            return false
        }

        let escapedSubject = appleScriptLiteral(subject)
        let recipientLines = recipientEmails.map { email in
            """
            make new to recipient at end of to recipients of newMessage with properties {email address:{name:"", address:\(appleScriptLiteral(email))}}
            """
        }.joined(separator: "\n        ")
        let attachmentLines = fileURLs.map { url in
            """
            make new attachment at end of attachments of newMessage with properties {file:(POSIX file \(appleScriptLiteral(url.path)) as alias)}
            """
        }.joined(separator: "\n        ")

        let script = """
        tell application "Microsoft Outlook"
            activate
            set newMessage to make new outgoing message with properties {subject:\(escapedSubject), content:""}
            open newMessage
            tell newMessage
                \(recipientLines)
                \(attachmentLines)
            end tell
            activate
        end tell
        """

        return runAppleScript(script)
    }

    private static func composeWithMailApp(fileURLs: [URL], subject: String, recipientEmails: [String]) -> Bool {
        let escapedSubject = appleScriptLiteral(subject)
        let attachmentList = fileURLs
            .map { "\"\($0.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ", ")
        let recipientLines = recipientEmails
            .map { "make new to recipient at end of to recipients with properties {address:\(appleScriptLiteral($0))}" }
            .joined(separator: "\n        ")

        let script = """
        tell application "Mail"
            activate
            set newMessage to make new outgoing message with properties {visible:true, subject:\(escapedSubject)}
            tell newMessage
                \(recipientLines)
                repeat with filePath in {\(attachmentList)}
                    make new attachment with properties {file name:(POSIX file filePath as alias)} at after the last paragraph
                end repeat
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
