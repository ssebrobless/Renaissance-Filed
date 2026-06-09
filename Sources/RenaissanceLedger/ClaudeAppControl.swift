import AppKit
import Foundation
import SwiftUI

struct ClaudeAppControlCommand: Codable, Identifiable, Hashable {
    var id: UUID
    var createdAt: String
    var action: String
    var parameters: [String: String]
    var lines: [[String: String]]?
    var requestedBy: String?
}

struct ClaudeAppControlResult: Codable, Identifiable, Hashable {
    var id: UUID
    var commandID: UUID
    var completedAt: String
    var status: String
    var message: String
    var selectedTab: String
    var visibleWindows: [String]
}

struct ClaudeDraftReview: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: String
    var createdAt: String
    var title: String
    var summary: String
    var customerID: Int64?
    var customerName: String?
    var parameters: [String: String]
    var lines: [[String: String]]
}

@MainActor
final class ClaudeAppControlStore: ObservableObject {
    static let shared = ClaudeAppControlStore()

    @Published var activeDraft: ClaudeDraftReview?
    @Published var lastResultMessage: String = ""

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var processedCommandIDs: Set<UUID> = []

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var controlRootURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("RenaissanceLedger/ClaudeControl", isDirectory: true)
    }

    var incomingURL: URL { controlRootURL.appendingPathComponent("incoming", isDirectory: true) }
    var completedURL: URL { controlRootURL.appendingPathComponent("completed", isDirectory: true) }
    var resultsURL: URL { controlRootURL.appendingPathComponent("results", isDirectory: true) }
    var memoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("RenaissanceLedger/ClaudeMemory/workflow-observations.jsonl")
    }

    func pollAndApply(model: AppViewModel, windowManager: WorkspaceWindowManager) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: incomingURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let commandFiles = files.filter { $0.pathExtension == "json" }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }

        for commandFile in commandFiles.prefix(3) {
            guard let data = try? Data(contentsOf: commandFile),
                  let command = try? decoder.decode(ClaudeAppControlCommand.self, from: data),
                  !processedCommandIDs.contains(command.id) else {
                continue
            }
            processedCommandIDs.insert(command.id)
            let result = apply(command, model: model, windowManager: windowManager)
            write(result: result)
            moveCompleted(commandFile)
        }
    }

    private func apply(_ command: ClaudeAppControlCommand, model: AppViewModel, windowManager: WorkspaceWindowManager) -> ClaudeAppControlResult {
        let normalizedAction = command.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let message: String

        switch normalizedAction {
        case "open_tab":
            message = openTab(command, model: model, windowManager: windowManager)
        case "open_window":
            message = openWindow(command, windowManager: windowManager)
        case "search_customer":
            let query = command.parameters["query"] ?? command.parameters["customerName"] ?? ""
            windowManager.session.centerMode = .customers
            windowManager.session.customerSearch = query
            windowManager.session.isCenterTrayExpanded = true
            windowManager.showCenterWindow()
            message = "Opened Customer Center and searched for \(query.isEmpty ? "all customers" : query)."
        case "open_customer":
            message = openCustomer(command, model: model, windowManager: windowManager)
        case "open_report":
            message = openReport(command, model: model, windowManager: windowManager)
        case "open_register":
            message = openRegister(command, model: model, windowManager: windowManager)
        case "write_check", "open_check_desk":
            windowManager.showCheckDeskForNewCheck()
            message = "Opened the Check Desk for a new check draft."
        case "open_help":
            windowManager.showHelpWindow()
            message = "Opened Help Me."
        case "open_tech_support":
            windowManager.showTechSupportWindow()
            message = "Opened Tech Support."
        case "create_estimate_draft", "create_invoice_draft", "create_expense_draft", "create_bill_draft", "create_sales_receipt_draft":
            message = showDraftReview(command, model: model, windowManager: windowManager)
        case "remember_workflow":
            message = rememberWorkflow(command)
        case "snapshot_state":
            message = "Captured current app state for Claude."
        default:
            message = "Unknown Claude app-control action: \(command.action)."
        }

        lastResultMessage = message
        return ClaudeAppControlResult(
            id: UUID(),
            commandID: command.id,
            completedAt: ISO8601DateFormatter().string(from: Date()),
            status: message.hasPrefix("Unknown") ? "failed" : "completed",
            message: message,
            selectedTab: model.selectedTab.rawValue,
            visibleWindows: visibleWindowTitles()
        )
    }

    private func openTab(_ command: ClaudeAppControlCommand, model: AppViewModel, windowManager: WorkspaceWindowManager) -> String {
        guard let rawTab = command.parameters["tab"] ?? command.parameters["name"],
              let tab = AppTab.resolve(rawTab) else {
            return "Unknown tab. Available tabs include workspace, mail, customers, vendors, lists, estimates, invoices, salesreceipts, expenses, bills, reports, sync, import, documents, and settings."
        }
        windowManager.openNavigatorRoute(tab)
        return "Opened Navigator tab \(tab.rawValue)."
    }

    private func openWindow(_ command: ClaudeAppControlCommand, windowManager: WorkspaceWindowManager) -> String {
        let rawKind = command.parameters["window"] ?? command.parameters["kind"] ?? ""
        switch rawKind.lowercased() {
        case "center", "customercenter", "customer_center", "customer/register":
            windowManager.showCenterWindow()
            return "Opened Customer Center / Register."
        case "reportcenter", "report_center":
            windowManager.showReportCenterWindow()
            return "Opened Report Center."
        case "report", "reportwindow", "report_window":
            windowManager.showReportWindow()
            return "Opened Report Window."
        case "navigator", "navigation":
            windowManager.showNavigatorWindow()
            return "Opened Navigator."
        case "checkdesk", "check_desk", "check":
            windowManager.showCheckDeskForNewCheck()
            return "Opened Check Desk."
        case "help", "helpme", "help_me":
            windowManager.showHelpWindow()
            return "Opened Help Me."
        case "techsupport", "tech_support":
            windowManager.showTechSupportWindow()
            return "Opened Tech Support."
        default:
            return "Unknown window \(rawKind)."
        }
    }

    private func openCustomer(_ command: ClaudeAppControlCommand, model: AppViewModel, windowManager: WorkspaceWindowManager) -> String {
        guard let customer = resolveCustomer(command.parameters, model: model) else {
            windowManager.session.centerMode = .customers
            windowManager.session.customerSearch = command.parameters["customerName"] ?? command.parameters["query"] ?? ""
            windowManager.session.isCenterTrayExpanded = true
            windowManager.showCenterWindow()
            return "Could not find an exact customer match. Opened Customer Center with the search filled in."
        }
        windowManager.openCustomerWorkspace(customerID: customer.id)
        return "Opened customer workspace for \(customer.displayName)."
    }

    private func openReport(_ command: ClaudeAppControlCommand, model: AppViewModel, windowManager: WorkspaceWindowManager) -> String {
        let rawReport = command.parameters["report"] ?? command.parameters["tab"] ?? "Historical QB P&L"
        guard let report = AppViewModel.reportTab(from: rawReport) else {
            windowManager.showReportCenterWindow()
            return "Unknown report \(rawReport). Opened Report Center."
        }
        let customer = resolveCustomer(command.parameters, model: model)
        windowManager.openReport(tab: report, customerID: customer?.id)
        return "Opened \(report.rawValue)\(customer.map { " for \($0.displayName)" } ?? "")."
    }

    private func openRegister(_ command: ClaudeAppControlCommand, model: AppViewModel, windowManager: WorkspaceWindowManager) -> String {
        windowManager.session.centerMode = .register
        windowManager.session.isCenterTrayExpanded = true
        windowManager.session.registerSearch = command.parameters["search"] ?? ""
        if let bankName = command.parameters["bankAccountName"] ?? command.parameters["account"] {
            if let account = model.accounts.first(where: { $0.name.localizedCaseInsensitiveContains(bankName) && $0.type == "asset" }) {
                windowManager.session.selectedBankAccountID = account.id
            }
        }
        if let mode = command.parameters["mode"]?.lowercased(), mode.contains("import") {
            windowManager.session.registerMode = .importedHistory
        } else {
            windowManager.session.registerMode = .checkRegister
        }
        windowManager.showCenterWindow()
        return "Opened the register workspace."
    }

    private func showDraftReview(_ command: ClaudeAppControlCommand, model: AppViewModel, windowManager: WorkspaceWindowManager) -> String {
        let customer = resolveCustomer(command.parameters, model: model)
        let kind = command.action.replacingOccurrences(of: "create_", with: "").replacingOccurrences(of: "_draft", with: "")
        let title = command.parameters["title"] ?? "Claude \(kind.replacingOccurrences(of: "_", with: " ").capitalized) Draft"
        let summary = command.parameters["summary"] ?? command.parameters["memo"] ?? "Claude prepared this draft for Dad to review before anything is saved."
        let draft = ClaudeDraftReview(
            id: command.id,
            kind: kind,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            title: title,
            summary: summary,
            customerID: customer?.id,
            customerName: customer?.displayName ?? command.parameters["customerName"],
            parameters: command.parameters,
            lines: command.lines ?? []
        )
        activeDraft = draft
        if let customer {
            windowManager.openCustomerWorkspace(customerID: customer.id)
        }
        windowManager.showClaudeControlWindow()
        return "Opened a Claude draft review for \(kind). Dad must review before saving anything."
    }

    private func rememberWorkflow(_ command: ClaudeAppControlCommand) -> String {
        let note = command.parameters["note"] ?? command.parameters["summary"] ?? command.parameters["workflow"] ?? ""
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No workflow note was provided."
        }
        let record: [String: Any] = [
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "source": "claudeAppControl",
            "note": note,
            "parameters": command.parameters,
        ]
        do {
            try fileManager.createDirectory(at: memoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            var line = String(data: data, encoding: .utf8) ?? "{}"
            line.append("\n")
            if fileManager.fileExists(atPath: memoryURL.path) {
                let handle = try FileHandle(forWritingTo: memoryURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: memoryURL, atomically: true, encoding: .utf8)
            }
            return "Saved this workflow note for future Claude help."
        } catch {
            return "Could not save workflow memory: \(error.localizedDescription)"
        }
    }

    private func resolveCustomer(_ parameters: [String: String], model: AppViewModel) -> CustomerRow? {
        if let idText = parameters["customerID"] ?? parameters["customerId"],
           let id = Int64(idText),
           let customer = model.customers.first(where: { $0.id == id }) {
            return customer
        }
        let query = (parameters["customerName"] ?? parameters["customer"] ?? parameters["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return model.customers.first { $0.displayName.localizedCaseInsensitiveCompare(query) == .orderedSame }
            ?? model.customers.first { $0.displayName.localizedCaseInsensitiveContains(query) || $0.company.localizedCaseInsensitiveContains(query) }
    }

    private func visibleWindowTitles() -> [String] {
        NSApp.windows
            .filter { $0.isVisible }
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func write(result: ClaudeAppControlResult) {
        do {
            try fileManager.createDirectory(at: resultsURL, withIntermediateDirectories: true)
            let data = try encoder.encode(result)
            try data.write(to: resultsURL.appendingPathComponent("\(result.commandID.uuidString).json"), options: .atomic)
        } catch {
            NSLog("Claude app-control result write failed: \(error.localizedDescription)")
        }
    }

    private func moveCompleted(_ commandFile: URL) {
        do {
            try fileManager.createDirectory(at: completedURL, withIntermediateDirectories: true)
            let destination = completedURL.appendingPathComponent(commandFile.lastPathComponent)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: commandFile, to: destination)
        } catch {
            try? fileManager.removeItem(at: commandFile)
        }
    }
}

struct ClaudeControlWindowView: View {
    @ObservedObject private var store = ClaudeAppControlStore.shared
    @EnvironmentObject private var windowManager: WorkspaceWindowManager
    @State private var requestText: String = ""
    @State private var isWorking: Bool = false
    @State private var statusMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude App Control")
                        .font(.title2.bold())
                    Text("Claude can navigate the app and prepare safe drafts here. Dad reviews before anything is saved.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
            }

            askClaudeCard

            if let draft = store.activeDraft {
                draftReview(draft)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ready for Claude commands", systemImage: "wand.and.stars")
                        .font(.headline)
                    Text(store.lastResultMessage.isEmpty ? "No draft is open right now." : store.lastResultMessage)
                        .foregroundStyle(AppTheme.bodyText)
                    Text("Claude can open app windows, search customers, open reports, switch to the register, show the Check Desk, and prepare review-only drafts.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 420)
        .background(AppTheme.surface)
    }

    private func draftReview(_ draft: ClaudeDraftReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.title)
                            .font(.headline)
                        Text(draft.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Spacer()
                    Button("Close Draft") {
                        store.activeDraft = nil
                    }
                    .buttonStyle(.renaissanceSecondary)
                }

                Text(draft.summary)
                    .foregroundStyle(AppTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)

                if let customerName = draft.customerName {
                    Label(customerName, systemImage: "person.crop.circle")
                        .foregroundStyle(AppTheme.bodyText)
                }

                if !draft.parameters.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Draft Fields")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink3)
                        ForEach(draft.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .top) {
                                Text(key)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink3)
                                    .frame(width: 130, alignment: .leading)
                                Text(value)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.bodyText)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(12)
                    .background(AppTheme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !draft.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Draft Lines")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink3)
                        ForEach(Array(draft.lines.enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Line \(index + 1)")
                                    .font(.caption.weight(.bold))
                                ForEach(line.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    Text("\(key): \(value)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.bodyText)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardFillSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                HStack {
                    Button("Open Customer") {
                        if let customerID = draft.customerID {
                            windowManager.openCustomerWorkspace(customerID: customerID)
                        }
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(draft.customerID == nil)

                    Button("Open Related Tab") {
                        openRelatedTab(for: draft.kind)
                    }
                    .buttonStyle(.renaissancePrimary)
                }
            }
        }
    }

    private func openRelatedTab(for kind: String) {
        switch kind {
        case "estimate":
            windowManager.openNavigatorRoute(.estimates)
        case "invoice":
            windowManager.openNavigatorRoute(.invoices)
        case "expense":
            windowManager.openNavigatorRoute(.expenses)
        case "bill":
            windowManager.openNavigatorRoute(.bills)
        case "sales_receipt":
            windowManager.openNavigatorRoute(.salesReceipts)
        default:
            windowManager.showNavigatorWindow()
        }
    }

    private var askClaudeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tell me what to enter", systemImage: "text.bubble")
                .font(.headline)
            Text("Type it in plain words — or press the dictation key and just say it. Example: “invoice C&D job 35 for 80 square feet of shower wall tile at 6.25 and a 150 dollar niche.” I’ll prepare a draft for you to review. Nothing is saved until you approve it.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $requestText)
                .font(.body)
                .frame(minHeight: 64)
                .padding(6)
                .background(AppTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.ink3.opacity(0.3)))
                .disabled(isWorking)
            HStack(spacing: 10) {
                Button(isWorking ? "Working…" : "Create Draft") { submitRequest() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(isWorking || requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isWorking { ProgressView().controlSize(.small) }
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func submitRequest() {
        let text = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        isWorking = true
        statusMessage = "Asking Claude…"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let script = home + "/renaissance-ledger/scripts/claude_data_entry.py"
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", script, text]
            var environment = ProcessInfo.processInfo.environment
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + existingPath
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var resultMessage: String
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    resultMessage = "Draft prepared — review it below."
                } else {
                    resultMessage = "Couldn’t prepare a draft. " + String(output.suffix(220))
                }
            } catch {
                resultMessage = "Error launching helper: \(error.localizedDescription)"
            }
            let finalMessage = resultMessage
            DispatchQueue.main.async {
                self.statusMessage = finalMessage
                self.isWorking = false
                if finalMessage.hasPrefix("Draft prepared") {
                    self.requestText = ""
                }
            }
        }
    }
}
