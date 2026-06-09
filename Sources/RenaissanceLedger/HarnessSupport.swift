import AppKit
import Foundation

private struct HarnessLaunchStateFile: Codable {
    var selectedTab: String?
    var reportTab: String?
    var reportYear: Int?
    var reportPeriod: String?
    var customerID: Int64?
    var estimateID: Int64?
    var invoiceID: Int64?
    var editEstimateID: Int64?
    var editInvoiceID: Int64?
    var openExpenseID: Int64?
    var updateEstimateMemoID: Int64?
    var updateEstimateMemoValue: String?
    var updateInvoiceMemoID: Int64?
    var updateInvoiceMemoValue: String?
    var emailDocumentID: Int64?
    var approveFirstOrderSheet: Bool?
    var openWriteCheck: Bool?
    var openCheckDesk: Bool?
    var reviewFirstOrderSheet: Bool?
    var previewEstimateItemQuery: String?
    var previewInvoiceItemQuery: String?
    var previewWriteCheckPayeeQuery: String?
    var previewEstimateInvoiceProgressChooser: Bool?
    var verifyInvoiceManualDescription: Bool?
    var emailEstimateOnOpen: Bool?
    var emailInvoiceOnOpen: Bool?
    var moneyInProofToken: String?
    var moneyOutProofToken: String?
    var jobCostingProofToken: String?
    var reportCorrectnessProofToken: String?
    var bankReconciliationProofToken: String?
    var navigationShellProof: Bool?
    var windowRecoveryProof: Bool?
    var windowRecoverySummaryPath: String?
    var snapshotPath: String?
    var snapshotDelaySeconds: Double?
}

enum AppTab: String, CaseIterable, Hashable {
    case workspace
    case mail
    case customers
    case vendors
    case lists
    case estimates
    case invoices
    case salesReceipts = "salesreceipts"
    case expenses
    case bills
    case reports
    case sync
    case importCenter = "import"
    case history
    case documents
    case settings

    static func resolve(_ rawValue: String) -> AppTab? {
        let normalized = rawValue.lowercased()
        if normalized == "home" {
            return .workspace
        }
        return AppTab(rawValue: normalized)
    }
}

struct HarnessLaunchConfiguration {
    let showMainWindow: Bool
    let selectedTab: AppTab?
    let reportTab: String?
    let reportYear: Int?
    let reportPeriod: String?
    let customerID: Int64?
    let estimateID: Int64?
    let invoiceID: Int64?
    let editEstimateID: Int64?
    let editInvoiceID: Int64?
    let openExpenseID: Int64?
    let updateEstimateMemoID: Int64?
    let updateEstimateMemoValue: String?
    let updateInvoiceMemoID: Int64?
    let updateInvoiceMemoValue: String?
    let emailDocumentID: Int64?
    let approveFirstOrderSheet: Bool
    let openWriteCheck: Bool
    let openCheckDesk: Bool
    let reviewFirstOrderSheet: Bool
    let previewEstimateItemQuery: String?
    let previewInvoiceItemQuery: String?
    let previewWriteCheckPayeeQuery: String?
    let previewEstimateInvoiceProgressChooser: Bool
    let verifyInvoiceManualDescription: Bool
    let emailEstimateOnOpen: Bool
    let emailInvoiceOnOpen: Bool
    let moneyInProofToken: String?
    let moneyOutProofToken: String?
    let jobCostingProofToken: String?
    let reportCorrectnessProofToken: String?
    let bankReconciliationProofToken: String?
    let navigationShellProof: Bool
    let windowRecoveryProof: Bool
    let windowRecoverySummaryPath: String?
    let snapshotPath: String?
    let snapshotDelaySeconds: Double?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        var showMainWindow = false
        var selectedTab: AppTab?
        var reportTab: String?
        var reportYear: Int?
        var reportPeriod: String?
        var customerID: Int64?
        var estimateID: Int64?
        var invoiceID: Int64?
        var editEstimateID: Int64?
        var editInvoiceID: Int64?
        var openExpenseID: Int64?
        var updateEstimateMemoID: Int64?
        var updateEstimateMemoValue: String?
        var updateInvoiceMemoID: Int64?
        var updateInvoiceMemoValue: String?
        var emailDocumentID: Int64?
        var approveFirstOrderSheet = false
        var openWriteCheck = false
        var openCheckDesk = false
        var reviewFirstOrderSheet = false
        var previewEstimateItemQuery: String?
        var previewInvoiceItemQuery: String?
        var previewWriteCheckPayeeQuery: String?
        var previewEstimateInvoiceProgressChooser = false
        var verifyInvoiceManualDescription = false
        var emailEstimateOnOpen = false
        var emailInvoiceOnOpen = false
        var moneyInProofToken: String?
        var moneyOutProofToken: String?
        var jobCostingProofToken: String?
        var reportCorrectnessProofToken: String?
        var bankReconciliationProofToken: String?
        var navigationShellProof = false
        var windowRecoveryProof = false
        var windowRecoverySummaryPath: String?
        var snapshotPath: String?
        var snapshotDelaySeconds: Double?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--harness-show-main-window":
                showMainWindow = true
            case "--harness-tab":
                if index + 1 < arguments.count {
                    selectedTab = AppTab.resolve(arguments[index + 1])
                    index += 1
                }
            case "--harness-report-tab":
                if index + 1 < arguments.count {
                    reportTab = arguments[index + 1]
                    index += 1
                }
            case "--harness-report-year":
                if index + 1 < arguments.count {
                    reportYear = Int(arguments[index + 1])
                    index += 1
                }
            case "--harness-report-period":
                if index + 1 < arguments.count {
                    reportPeriod = arguments[index + 1]
                    index += 1
                }
            case "--harness-open-customer":
                if index + 1 < arguments.count {
                    customerID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-open-estimate":
                if index + 1 < arguments.count {
                    estimateID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-open-invoice":
                if index + 1 < arguments.count {
                    invoiceID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-edit-estimate":
                if index + 1 < arguments.count {
                    editEstimateID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-edit-invoice":
                if index + 1 < arguments.count {
                    editInvoiceID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-open-expense":
                if index + 1 < arguments.count {
                    openExpenseID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-update-estimate-memo":
                if index + 2 < arguments.count {
                    updateEstimateMemoID = Int64(arguments[index + 1])
                    updateEstimateMemoValue = arguments[index + 2]
                    index += 2
                }
            case "--harness-update-invoice-memo":
                if index + 2 < arguments.count {
                    updateInvoiceMemoID = Int64(arguments[index + 1])
                    updateInvoiceMemoValue = arguments[index + 2]
                    index += 2
                }
            case "--harness-email-document":
                if index + 1 < arguments.count {
                    emailDocumentID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-approve-first-order-sheet":
                approveFirstOrderSheet = true
            case "--harness-open-write-check":
                openWriteCheck = true
            case "--harness-open-check-desk":
                openCheckDesk = true
            case "--harness-review-first-order-sheet":
                reviewFirstOrderSheet = true
            case "--harness-preview-estimate-item-query":
                if index + 1 < arguments.count {
                    previewEstimateItemQuery = arguments[index + 1]
                    index += 1
                }
            case "--harness-preview-invoice-item-query":
                if index + 1 < arguments.count {
                    previewInvoiceItemQuery = arguments[index + 1]
                    index += 1
                }
            case "--harness-preview-write-check-payee-query":
                if index + 1 < arguments.count {
                    previewWriteCheckPayeeQuery = arguments[index + 1]
                    index += 1
                }
            case "--harness-preview-estimate-invoice-progress-chooser":
                previewEstimateInvoiceProgressChooser = true
            case "--harness-verify-invoice-manual-description":
                verifyInvoiceManualDescription = true
            case "--harness-email-estimate-on-open":
                emailEstimateOnOpen = true
            case "--harness-email-invoice-on-open":
                emailInvoiceOnOpen = true
            case "--harness-prove-money-in-spine":
                if index + 1 < arguments.count {
                    moneyInProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-money-out-spine":
                if index + 1 < arguments.count {
                    moneyOutProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-job-costing":
                if index + 1 < arguments.count {
                    jobCostingProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-report-correctness":
                if index + 1 < arguments.count {
                    reportCorrectnessProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-bank-reconciliation":
                if index + 1 < arguments.count {
                    bankReconciliationProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-navigation-shell":
                navigationShellProof = true
            case "--harness-prove-window-recovery":
                windowRecoveryProof = true
            case "--harness-window-recovery-summary-path":
                if index + 1 < arguments.count {
                    windowRecoverySummaryPath = arguments[index + 1]
                    index += 1
                }
            case "--harness-snapshot-path":
                if index + 1 < arguments.count {
                    snapshotPath = arguments[index + 1]
                    index += 1
                }
            case "--harness-snapshot-delay":
                if index + 1 < arguments.count {
                    snapshotDelaySeconds = Double(arguments[index + 1])
                    index += 1
                }
            default:
                break
            }
            index += 1
        }

        if let persistedState = Self.consumePersistedState() {
            if let rawTab = persistedState.selectedTab, let tab = AppTab.resolve(rawTab) {
                selectedTab = tab
            }
            if let persistedReportTab = persistedState.reportTab {
                reportTab = persistedReportTab
            }
            if let persistedReportYear = persistedState.reportYear {
                reportYear = persistedReportYear
            }
            if let persistedReportPeriod = persistedState.reportPeriod {
                reportPeriod = persistedReportPeriod
            }
            if let persistedCustomerID = persistedState.customerID {
                customerID = persistedCustomerID
            }
            if let persistedEstimateID = persistedState.estimateID {
                estimateID = persistedEstimateID
            }
            if let persistedInvoiceID = persistedState.invoiceID {
                invoiceID = persistedInvoiceID
            }
            if let persistedEditEstimateID = persistedState.editEstimateID {
                editEstimateID = persistedEditEstimateID
            }
            if let persistedEditInvoiceID = persistedState.editInvoiceID {
                editInvoiceID = persistedEditInvoiceID
            }
            if let persistedOpenExpenseID = persistedState.openExpenseID {
                openExpenseID = persistedOpenExpenseID
            }
            if let persistedUpdateEstimateMemoID = persistedState.updateEstimateMemoID {
                updateEstimateMemoID = persistedUpdateEstimateMemoID
            }
            if let persistedUpdateEstimateMemoValue = persistedState.updateEstimateMemoValue {
                updateEstimateMemoValue = persistedUpdateEstimateMemoValue
            }
            if let persistedUpdateInvoiceMemoID = persistedState.updateInvoiceMemoID {
                updateInvoiceMemoID = persistedUpdateInvoiceMemoID
            }
            if let persistedUpdateInvoiceMemoValue = persistedState.updateInvoiceMemoValue {
                updateInvoiceMemoValue = persistedUpdateInvoiceMemoValue
            }
            if let persistedEmailDocumentID = persistedState.emailDocumentID {
                emailDocumentID = persistedEmailDocumentID
            }
            if let persistedApproveFirstOrderSheet = persistedState.approveFirstOrderSheet {
                approveFirstOrderSheet = persistedApproveFirstOrderSheet
            }
            if let persistedOpenWriteCheck = persistedState.openWriteCheck {
                openWriteCheck = persistedOpenWriteCheck
            }
            if let persistedOpenCheckDesk = persistedState.openCheckDesk {
                openCheckDesk = persistedOpenCheckDesk
            }
            if let persistedReviewFirstOrderSheet = persistedState.reviewFirstOrderSheet {
                reviewFirstOrderSheet = persistedReviewFirstOrderSheet
            }
            if let persistedPreviewEstimateItemQuery = persistedState.previewEstimateItemQuery {
                previewEstimateItemQuery = persistedPreviewEstimateItemQuery
            }
            if let persistedPreviewInvoiceItemQuery = persistedState.previewInvoiceItemQuery {
                previewInvoiceItemQuery = persistedPreviewInvoiceItemQuery
            }
            if let persistedPreviewWriteCheckPayeeQuery = persistedState.previewWriteCheckPayeeQuery {
                previewWriteCheckPayeeQuery = persistedPreviewWriteCheckPayeeQuery
            }
            if let persistedPreviewEstimateInvoiceProgressChooser = persistedState.previewEstimateInvoiceProgressChooser {
                previewEstimateInvoiceProgressChooser = persistedPreviewEstimateInvoiceProgressChooser
            }
            if let persistedVerifyInvoiceManualDescription = persistedState.verifyInvoiceManualDescription {
                verifyInvoiceManualDescription = persistedVerifyInvoiceManualDescription
            }
            if let persistedEmailEstimateOnOpen = persistedState.emailEstimateOnOpen {
                emailEstimateOnOpen = persistedEmailEstimateOnOpen
            }
            if let persistedEmailInvoiceOnOpen = persistedState.emailInvoiceOnOpen {
                emailInvoiceOnOpen = persistedEmailInvoiceOnOpen
            }
            if let persistedMoneyInProofToken = persistedState.moneyInProofToken {
                moneyInProofToken = persistedMoneyInProofToken
            }
            if let persistedMoneyOutProofToken = persistedState.moneyOutProofToken {
                moneyOutProofToken = persistedMoneyOutProofToken
            }
            if let persistedJobCostingProofToken = persistedState.jobCostingProofToken {
                jobCostingProofToken = persistedJobCostingProofToken
            }
            if let persistedReportCorrectnessProofToken = persistedState.reportCorrectnessProofToken {
                reportCorrectnessProofToken = persistedReportCorrectnessProofToken
            }
            if let persistedBankReconciliationProofToken = persistedState.bankReconciliationProofToken {
                bankReconciliationProofToken = persistedBankReconciliationProofToken
            }
            if let persistedNavigationShellProof = persistedState.navigationShellProof {
                navigationShellProof = persistedNavigationShellProof
            }
            if let persistedWindowRecoveryProof = persistedState.windowRecoveryProof {
                windowRecoveryProof = persistedWindowRecoveryProof
            }
            if let persistedWindowRecoverySummaryPath = persistedState.windowRecoverySummaryPath {
                windowRecoverySummaryPath = persistedWindowRecoverySummaryPath
            }
            if let persistedSnapshotPath = persistedState.snapshotPath {
                snapshotPath = persistedSnapshotPath
            }
            if let persistedSnapshotDelaySeconds = persistedState.snapshotDelaySeconds {
                snapshotDelaySeconds = persistedSnapshotDelaySeconds
            }
        }

        self.showMainWindow = showMainWindow
        self.selectedTab = selectedTab
        self.reportTab = reportTab
        self.reportYear = reportYear
        self.reportPeriod = reportPeriod
        self.customerID = customerID
        self.estimateID = estimateID
        self.invoiceID = invoiceID
        self.editEstimateID = editEstimateID
        self.editInvoiceID = editInvoiceID
        self.openExpenseID = openExpenseID
        self.updateEstimateMemoID = updateEstimateMemoID
        self.updateEstimateMemoValue = updateEstimateMemoValue
        self.updateInvoiceMemoID = updateInvoiceMemoID
        self.updateInvoiceMemoValue = updateInvoiceMemoValue
        self.emailDocumentID = emailDocumentID
        self.approveFirstOrderSheet = approveFirstOrderSheet
        self.openWriteCheck = openWriteCheck
        self.openCheckDesk = openCheckDesk
        self.reviewFirstOrderSheet = reviewFirstOrderSheet
        self.previewEstimateItemQuery = previewEstimateItemQuery
        self.previewInvoiceItemQuery = previewInvoiceItemQuery
        self.previewWriteCheckPayeeQuery = previewWriteCheckPayeeQuery
        self.previewEstimateInvoiceProgressChooser = previewEstimateInvoiceProgressChooser
        self.verifyInvoiceManualDescription = verifyInvoiceManualDescription
        self.emailEstimateOnOpen = emailEstimateOnOpen
        self.emailInvoiceOnOpen = emailInvoiceOnOpen
        self.moneyInProofToken = moneyInProofToken
        self.moneyOutProofToken = moneyOutProofToken
        self.jobCostingProofToken = jobCostingProofToken
        self.reportCorrectnessProofToken = reportCorrectnessProofToken
        self.bankReconciliationProofToken = bankReconciliationProofToken
        self.navigationShellProof = navigationShellProof
        self.windowRecoveryProof = windowRecoveryProof
        self.windowRecoverySummaryPath = windowRecoverySummaryPath
        self.snapshotPath = snapshotPath
        self.snapshotDelaySeconds = snapshotDelaySeconds
    }

    private static func consumePersistedState() -> HarnessLaunchStateFile? {
        let url = harnessLaunchStateURL()
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(HarnessLaunchStateFile.self, from: data) else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return state
    }
}

func harnessLaunchStateURL() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return support
        .appendingPathComponent("RenaissanceHarness", isDirectory: true)
        .appendingPathComponent("state", isDirectory: true)
        .appendingPathComponent("ledger-launch.json")
}

func presentHarnessWindows(retries: Int = 8, delay: TimeInterval = 0.35) {
    guard retries > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows.filter { !isWorkspaceBootstrapWindow($0) }
        if !windows.isEmpty {
            windows.forEach { window in
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }

        if windows.isEmpty || windows.allSatisfy({ !$0.isVisible }) {
            presentHarnessWindows(retries: retries - 1, delay: delay)
        }
    }
}

func scheduleHarnessSnapshotIfNeeded(path: String?, delay: TimeInterval?) {
    guard let path, !path.isEmpty else { return }
    let wait = max(delay ?? 2.0, 0.5)
    appendHarnessLog("schedule snapshot path=\(path) delay=\(wait)")
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
        captureHarnessSnapshot(to: URL(fileURLWithPath: path), retries: 10)
    }
}

private func captureHarnessSnapshot(to url: URL, retries: Int) {
    guard retries > 0 else { return }

    let windows = NSApp.windows.filter { !isWorkspaceBootstrapWindow($0) }
    let keyWindow = NSApp.keyWindow.flatMap { isWorkspaceBootstrapWindow($0) ? nil : $0 }
    let mainWindow = NSApp.mainWindow.flatMap { isWorkspaceBootstrapWindow($0) ? nil : $0 }
    let candidate = keyWindow?.attachedSheet
        ?? mainWindow?.attachedSheet
        ?? windows.first(where: { $0.isVisible && $0.sheetParent != nil })
        ?? keyWindow
        ?? mainWindow
        ?? windows.first(where: { $0.isVisible })

    guard let view = candidate?.contentView else {
        appendHarnessLog("snapshot retry no visible contentView retries=\(retries)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            captureHarnessSnapshot(to: url, retries: retries - 1)
        }
        return
    }

    view.layoutSubtreeIfNeeded()
    let bounds = view.bounds.integral
    guard bounds.width > 10, bounds.height > 10,
          let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
        appendHarnessLog("snapshot retry invalid bounds=\(bounds) retries=\(retries)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            captureHarnessSnapshot(to: url, retries: retries - 1)
        }
        return
    }

    view.cacheDisplay(in: bounds, to: rep)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        appendHarnessLog("snapshot retry png encode failed retries=\(retries)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            captureHarnessSnapshot(to: url, retries: retries - 1)
        }
        return
    }

    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? pngData.write(to: url, options: .atomic)
    appendHarnessLog("snapshot wrote \(url.path) bytes=\(pngData.count)")
}

func appendHarnessLog(_ message: String) {
    let url = harnessLaunchStateURL().deletingLastPathComponent().appendingPathComponent("ledger-harness.log")
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

private func isWorkspaceBootstrapWindow(_ window: NSWindow) -> Bool {
    window.identifier == workspaceBootstrapWindowIdentifier || window.title == "Renaissance Bootstrap"
}
