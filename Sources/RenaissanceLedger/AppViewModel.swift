import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private enum HarnessDataMutationError: LocalizedError {
    case invalidToken
    case paymentMissing
    case depositAccountMissing

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Harness money-in proof token was empty or invalid."
        case .paymentMissing:
            return "Harness money-in proof did not create a payment row."
        case .depositAccountMissing:
            return "Harness money-in proof could not find a bank-style asset account for the deposit."
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var importSessions: [ImportSessionRow] = []
    @Published var transactions: [TransactionRow] = []
    @Published var invoices: [InvoiceRow] = []
    @Published var payouts: [PayoutRow] = []
    @Published var documents: [DocumentRow] = []
    @Published var issues: [ImportIssueRow] = []
    @Published var statusMessage = "Ready"
    @Published var isImporting = false

    @Published var transactionSearch = ""
    @Published var invoiceSearch = ""
    @Published var payoutSearch = ""
    @Published var documentSearch = ""

    // Native data entry
    @Published var customers: [CustomerRow] = []
    @Published var jobs: [JobRow] = []
    @Published var vendors: [VendorRow] = []
    @Published var accounts: [AccountRow] = []
    @Published var paymentTerms: [PaymentTermRow] = []
    @Published var paymentMethods: [PaymentMethodRow] = []
    @Published var estimates: [EstimateRow] = []
    @Published var nativeInvoices: [NativeInvoiceRow] = []
    @Published var salesReceipts: [SalesReceiptRow] = []
    @Published var expenses: [ExpenseRow] = []
    @Published var serviceItems: [ServiceItemRow] = []
    @Published var bills: [BillRow] = []
    @Published var companyInfo: CompanyInfo = CompanyInfo()
    @Published var selectedTab: AppTab
    @Published var orderSheets: [OrderSheetRow] = []
    @Published var isImportingOrderSheets = false
    @Published var orderSheetInboxSettings: OrderSheetInboxSettings
    @Published var orderSheetApprovalSettings: OrderSheetApprovalSettings
    @Published var mailReviewSettings: MailReviewSettings
    @Published var mailReviewSnapshot: MailInboxSnapshot = .empty
    @Published var isRefreshingMailReview = false
    @Published var isPerformingMailReviewAction = false
    @Published var mailReviewLastError: String = ""
    @Published var mailHistorySearchResults: [MailHistoryMessage] = []
    @Published var isSearchingMailHistory = false
    @Published var mailRecentSentMessages: [MailHistoryMessage] = []
    @Published var isLoadingRecentSentMail = false
    @Published var mailBodyCache: [String: String] = [:]
    @Published var mailBodyLoadingKey: String?
    @Published var duplicateWarningSettings: DuplicateWarningSettings
    @Published var paymentWorkflowSettings: PaymentWorkflowSettings
    @Published var checkWorkflowSettings: CheckWorkflowSettings
    @Published var oldQBSyncSettings: OldQBSyncSettings
    @Published var oldQBSyncSnapshot: OldQBSyncSnapshot

    let db = SQLiteDatabase.shared
    let orderSheetStore = OrderSheetStagingStore.shared
    let harnessLaunch: HarnessLaunchConfiguration
    private var orderSheetInboxTimer: Timer?
    private var isScanningOrderSheetInbox = false
    private var isWarmingDocumentReadabilityCache = false
    private var pendingCustomerID: Int64?
    private var pendingReportTab: String?
    private var pendingReportYear: Int?
    private var pendingReportPeriod: String?
    private var pendingReportCustomerID: Int64?
    private var pendingEstimateID: Int64?
    private var pendingInvoiceID: Int64?
    private var pendingEditEstimateID: Int64?
    private var pendingEditInvoiceID: Int64?
    private var pendingOpenExpenseID: Int64?
    private var pendingEmailDocumentID: Int64?
    private var pendingOpenWriteCheck = false
    private var pendingReviewFirstOrderSheet = false
    private var pendingPreviewEstimateItemQuery: String?
    private var pendingPreviewInvoiceItemQuery: String?
    private var pendingPreviewWriteCheckPayeeQuery: String?
    private var pendingPreviewEstimateInvoiceProgressChooser = false
    private var pendingVerifyInvoiceManualDescription = false
    private var pendingEmailEstimateOnOpen = false
    private var pendingEmailInvoiceOnOpen = false
    private var pendingMoneyInProofToken: String?
    private var pendingMoneyOutProofToken: String?
    private var pendingJobCostingProofToken: String?
    private var pendingReportCorrectnessProofToken: String?
    private var pendingBankReconciliationProofToken: String?

    init() {
        orderSheetInboxSettings = OrderSheetInboxSettings.load()
        orderSheetApprovalSettings = OrderSheetApprovalSettings.load()
        mailReviewSettings = MailReviewSettings.load()
        duplicateWarningSettings = DuplicateWarningSettings.load()
        paymentWorkflowSettings = PaymentWorkflowSettings.load()
        checkWorkflowSettings = CheckWorkflowSettings.load()
        oldQBSyncSettings = OldQBSyncSettings.load()
        oldQBSyncSnapshot = OldQBSyncSnapshot()
        harnessLaunch = HarnessLaunchConfiguration()
        if harnessLaunch.openWriteCheck {
            selectedTab = .expenses
        } else {
            selectedTab = harnessLaunch.selectedTab ?? .workspace
        }
        pendingCustomerID = harnessLaunch.customerID
        pendingReportTab = harnessLaunch.reportTab
        pendingReportYear = harnessLaunch.reportYear
        pendingReportPeriod = harnessLaunch.reportPeriod
        pendingEstimateID = harnessLaunch.estimateID
        pendingInvoiceID = harnessLaunch.invoiceID
        pendingEditEstimateID = harnessLaunch.editEstimateID
        pendingEditInvoiceID = harnessLaunch.editInvoiceID
        pendingOpenExpenseID = harnessLaunch.openExpenseID
        pendingEmailDocumentID = harnessLaunch.emailDocumentID
        pendingOpenWriteCheck = harnessLaunch.openWriteCheck
        pendingReviewFirstOrderSheet = harnessLaunch.reviewFirstOrderSheet
        pendingPreviewEstimateItemQuery = harnessLaunch.previewEstimateItemQuery
        pendingPreviewInvoiceItemQuery = harnessLaunch.previewInvoiceItemQuery
        pendingPreviewWriteCheckPayeeQuery = harnessLaunch.previewWriteCheckPayeeQuery
        pendingPreviewEstimateInvoiceProgressChooser = harnessLaunch.previewEstimateInvoiceProgressChooser
        pendingVerifyInvoiceManualDescription = harnessLaunch.verifyInvoiceManualDescription
        pendingEmailEstimateOnOpen = harnessLaunch.emailEstimateOnOpen
        pendingEmailInvoiceOnOpen = harnessLaunch.emailInvoiceOnOpen
        pendingMoneyInProofToken = harnessLaunch.moneyInProofToken
        pendingMoneyOutProofToken = harnessLaunch.moneyOutProofToken
        pendingJobCostingProofToken = harnessLaunch.jobCostingProofToken
        pendingReportCorrectnessProofToken = harnessLaunch.reportCorrectnessProofToken
        pendingBankReconciliationProofToken = harnessLaunch.bankReconciliationProofToken
        appendHarnessLog(
            "launch selectedTab=\(selectedTab.rawValue) " +
            "editEstimateID=\(pendingEditEstimateID.map(String.init) ?? "-") " +
            "editInvoiceID=\(pendingEditInvoiceID.map(String.init) ?? "-") " +
            "openExpenseID=\(pendingOpenExpenseID.map(String.init) ?? "-") " +
            "emailDocumentID=\(pendingEmailDocumentID.map(String.init) ?? "-") " +
            "approveFirstOrderSheet=\(harnessLaunch.approveFirstOrderSheet) " +
            "openWriteCheck=\(pendingOpenWriteCheck) " +
            "reviewFirstOrderSheet=\(pendingReviewFirstOrderSheet) " +
            "previewEstimateItemQuery=\(pendingPreviewEstimateItemQuery ?? "-") " +
            "previewInvoiceItemQuery=\(pendingPreviewInvoiceItemQuery ?? "-") " +
            "previewWriteCheckPayeeQuery=\(pendingPreviewWriteCheckPayeeQuery ?? "-") " +
            "previewEstimateInvoiceProgressChooser=\(pendingPreviewEstimateInvoiceProgressChooser) " +
            "verifyInvoiceManualDescription=\(pendingVerifyInvoiceManualDescription) " +
            "emailEstimateOnOpen=\(pendingEmailEstimateOnOpen) " +
            "emailInvoiceOnOpen=\(pendingEmailInvoiceOnOpen) " +
            "moneyInProofToken=\(pendingMoneyInProofToken ?? "-") " +
            "moneyOutProofToken=\(pendingMoneyOutProofToken ?? "-") " +
            "jobCostingProofToken=\(pendingJobCostingProofToken ?? "-") " +
            "reportCorrectnessProofToken=\(pendingReportCorrectnessProofToken ?? "-") " +
            "bankReconciliationProofToken=\(pendingBankReconciliationProofToken ?? "-")"
        )
        do {
            try db.open()
            performSandboxHarnessDataMutationsIfNeeded()
            refreshAll()
        } catch {
            statusMessage = "Database error: \(error.localizedDescription)"
        }
        configureOrderSheetInboxMonitoring()
    }

    deinit {
        orderSheetInboxTimer?.invalidate()
    }

    func importFromFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Select Lexar USB root or RenaissanceTransfer folder"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        importFromFolder(url)
    }

    func refreshAll() {
        refreshImportSessions()
        refreshTransactions()
        refreshInvoices()
        refreshPayouts()
        refreshDocuments()
        refreshIssues()
        refreshCustomers()
        refreshJobs()
        refreshVendors()
        refreshAccounts()
        refreshPaymentTerms()
        refreshPaymentMethods()
        refreshEstimates()
        refreshNativeInvoices()
        refreshSalesReceipts()
        refreshExpenses()
        refreshServiceItems()
        refreshBills()
        refreshCompanyInfo()
        refreshOrderSheets()
        if mailReviewSettings.isEnabled && mailReviewSettings.autoRefreshOnLaunch {
            refreshMailReview()
        }
    }

    func applyHarnessPresentationIfNeeded() {
        guard harnessLaunch.showMainWindow else { return }
        presentHarnessWindows(retries: 10, delay: 0.35)
        scheduleHarnessSnapshotIfNeeded(
            path: harnessLaunch.snapshotPath,
            delay: harnessLaunch.snapshotDelaySeconds
        )
    }

    func peekPendingCustomerID() -> Int64? { pendingCustomerID }

    func peekPendingReportTab() -> String? { pendingReportTab }

    func peekPendingReportYear() -> Int? { pendingReportYear }

    func peekPendingReportPeriod() -> String? { pendingReportPeriod }

    func peekPendingReportCustomerID() -> Int64? { pendingReportCustomerID }

    func clearPendingReportRoute() {
        pendingReportTab = nil
        pendingReportYear = nil
        pendingReportPeriod = nil
        pendingReportCustomerID = nil
    }

    func openCustomerStatementReport(customerID: Int64) {
        WorkspaceWindowManager.shared.openReport(tab: .statement, customerID: customerID)
        pendingReportTab = "statement"
        pendingReportCustomerID = customerID
        selectedTab = .reports
    }

    func openCustomerReportCenter(customerID: Int64) {
        WorkspaceWindowManager.shared.showReportCenterWindow()
        WorkspaceWindowManager.shared.openReport(tab: .statement, customerID: customerID)
        pendingReportTab = "statement"
        pendingReportCustomerID = customerID
        selectedTab = .reports
    }

    func openReportCenter(tab: String, customerID: Int64? = nil) {
        if let reportTab = AppViewModel.reportTab(from: tab) {
            WorkspaceWindowManager.shared.showReportCenterWindow()
            WorkspaceWindowManager.shared.openReport(tab: reportTab, customerID: customerID)
        }
        pendingReportTab = tab
        pendingReportCustomerID = customerID
        selectedTab = .reports
    }

    func saveDuplicateWarningSettings(_ settings: DuplicateWarningSettings) {
        duplicateWarningSettings = settings
        settings.save()
    }

    func savePaymentWorkflowSettings(_ settings: PaymentWorkflowSettings) {
        paymentWorkflowSettings = settings
        settings.save()
    }

    func saveCheckWorkflowSettings(_ settings: CheckWorkflowSettings) {
        checkWorkflowSettings = settings
        settings.save()
    }

    private func performSandboxHarnessDataMutationsIfNeeded() {
        guard ProcessInfo.processInfo.environment["RENAISSANCE_LEDGER_SANDBOX_MODE"] == "1" else {
            return
        }

        do {
            if let estimateID = harnessLaunch.updateEstimateMemoID,
               let memo = harnessLaunch.updateEstimateMemoValue,
               let estimate = try db.fetchEstimate(id: estimateID) {
                let lines = try db.fetchEstimateLines(estimateID: estimateID)
                    .map { (description: $0.description, quantity: $0.quantity, rate: $0.rate, amount: $0.amount) }
                try db.updateEstimateWithLines(
                    id: estimate.id,
                    number: estimate.estimateNumber,
                    customerID: estimate.customerID,
                    jobID: estimate.jobID == 0 ? nil : estimate.jobID,
                    issueDate: estimate.issueDate,
                    validUntil: estimate.validUntil,
                    memo: memo,
                    total: estimate.total,
                    status: estimate.status,
                    lines: lines,
                    customerNameOverride: estimate.customerNameOverride
                )
                appendHarnessLog("sandbox updated estimate memo id=\(estimateID)")
            }

            if let invoiceID = harnessLaunch.updateInvoiceMemoID,
               let memo = harnessLaunch.updateInvoiceMemoValue,
               let invoice = try db.fetchInvoice(id: invoiceID) {
                let lines = try db.fetchInvoiceLines(invoiceID: invoiceID)
                    .map { (description: $0.description, quantity: $0.quantity, rate: $0.rate, amount: $0.amount) }
                try db.updateInvoiceWithLines(
                    id: invoice.id,
                    number: invoice.invoiceNumber,
                    customerID: invoice.customerID,
                    jobID: invoice.jobID == 0 ? nil : invoice.jobID,
                    issueDate: invoice.issueDate,
                    dueDate: invoice.dueDate,
                    memo: memo,
                    total: invoice.total,
                    lines: lines,
                    customerNameOverride: invoice.customerNameOverride
                )
                appendHarnessLog("sandbox updated invoice memo id=\(invoiceID)")
            }

            if harnessLaunch.approveFirstOrderSheet {
                try approveFirstSandboxOrderSheetForHarness()
            }

            if let token = harnessLaunch.moneyInProofToken {
                try proveMoneyInSpineForHarness(token: token)
            }

            if let token = harnessLaunch.moneyOutProofToken {
                try proveMoneyOutSpineForHarness(token: token)
            }

            if let token = harnessLaunch.jobCostingProofToken {
                try proveJobCostingForHarness(token: token)
            }

            if let token = harnessLaunch.reportCorrectnessProofToken {
                try proveReportCorrectnessForHarness(token: token)
            }

            if let token = harnessLaunch.bankReconciliationProofToken {
                try proveBankReconciliationForHarness(token: token)
            }
        } catch {
            statusMessage = "Harness sandbox mutation failed: \(error.localizedDescription)"
            appendHarnessLog("sandbox mutation failed \(error.localizedDescription)")
        }
    }

    private func proveMoneyInSpineForHarness(token: String) throws {
        let safeToken = token.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24)
        guard !safeToken.isEmpty else {
            throw HarnessDataMutationError.invalidToken
        }

        let proofID = String(safeToken)
        let customerID = try db.insertCustomer(
            name: "SANDBOX Money-In \(proofID)",
            company: "SANDBOX Harness",
            primaryContact: "Renaissance Harness",
            email: "sandbox@example.invalid",
            phone: "",
            address: "Sandbox Only",
            city: "",
            state: "",
            zip: ""
        )
        let jobID = try db.insertJob(
            customerID: customerID,
            name: "SANDBOX Job \(proofID)",
            status: "active",
            siteAddress: "Sandbox Only",
            notes: "SANDBOX money-in proof job \(proofID)"
        )

        let formatter = DateFormatter.isoDate
        let issueDate = formatter.string(from: Date())
        let dueDate = formatter.string(from: Date().addingTimeInterval(14 * 86_400))
        let amount = 123.45
        let estimateTotal = amount * 2
        let estimateNumber = "SANDBOX-EST-\(proofID)"
        let invoiceNumber = "SANDBOX-INV-\(proofID)"
        let paymentReference = "SANDBOX-PAY-\(proofID)"
        let depositReference = "SANDBOX-DEP-\(proofID)"

        let estimateID = try db.saveEstimateWithLines(
            number: estimateNumber,
            customerID: customerID,
            issueDate: issueDate,
            validUntil: dueDate,
            memo: "SANDBOX progress estimate proof \(proofID)",
            total: estimateTotal,
            status: "accepted",
            lines: [
                (
                    description: "SANDBOX progress invoice full estimate proof",
                    quantity: 1,
                    rate: estimateTotal,
                    amount: estimateTotal
                )
            ],
            jobID: jobID
        )

        let invoiceID = try db.saveInvoiceWithLines(
            number: invoiceNumber,
            customerID: customerID,
            issueDate: issueDate,
            dueDate: dueDate,
            memo: "SANDBOX 50 percent progress invoice proof \(proofID)",
            total: amount,
            lines: [
                (
                    description: "SANDBOX progress invoice half of estimate",
                    quantity: 1,
                    rate: amount,
                    amount: amount
                )
            ],
            jobID: jobID
        )

        try db.linkEstimateToInvoice(
            estimateID: estimateID,
            invoiceID: invoiceID,
            mode: .percentOfEstimate,
            percentValue: 50,
            shouldMarkEstimateConverted: false,
            sourceNote: "SANDBOX money-in progress proof \(proofID)"
        )

        guard let paymentID = try db.recordCustomerPayment(
            customerID: customerID,
            paymentDate: issueDate,
            paymentAmount: amount,
            method: "check",
            reference: paymentReference,
            memo: "SANDBOX receive payment proof \(proofID)",
            depositAccountID: nil,
            cashAllocations: [(invoiceID: invoiceID, amount: amount)],
            creditApplications: []
        ) else {
            throw HarnessDataMutationError.paymentMissing
        }

        guard let depositAccountID = try db.fetchAccounts(type: "asset").first(where: {
            $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        })?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }

        let depositID = try db.recordDeposit(
            paymentIDs: [paymentID],
            depositDate: issueDate,
            destinationAccountID: depositAccountID,
            reference: depositReference,
            memo: "SANDBOX bank deposit proof \(proofID)"
        )

        appendHarnessLog(
            "sandbox money-in proof token=\(proofID) customerID=\(customerID) jobID=\(jobID) estimateID=\(estimateID) invoiceID=\(invoiceID) paymentID=\(paymentID) depositID=\(depositID)"
        )
    }

    private func proveMoneyOutSpineForHarness(token: String) throws {
        let safeToken = token.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24)
        guard !safeToken.isEmpty else {
            throw HarnessDataMutationError.invalidToken
        }

        let proofID = String(safeToken)
        let vendorID = try db.insertVendor(
            name: "SANDBOX Payee \(proofID)",
            company: "SANDBOX Harness",
            primaryContact: "Renaissance Harness",
            phone: "",
            address: "Sandbox Only",
            ein: "",
            is1099: false,
            isInternalSelf: false
        )

        guard let expenseAccountID = try db.fetchAccounts(type: "expense").first?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }
        guard let paymentAccountID = try db.fetchAccounts(type: "asset").first(where: {
            $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        })?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }

        let formatter = DateFormatter.isoDate
        let billDate = formatter.string(from: Date())
        let dueDate = formatter.string(from: Date().addingTimeInterval(10 * 86_400))
        let billAmount = 210.25
        let checkAmount = 44.75
        let billCheckNumber = "91\(String(proofID.suffix(4)))"
        let immediateCheckNumber = "92\(String(proofID.suffix(4)))"

        let billID = try db.insertBill(
            vendorNameOverride: "SANDBOX Payee \(proofID)",
            vendorID: vendorID,
            billDate: billDate,
            dueDate: dueDate,
            amount: billAmount,
            accountID: expenseAccountID,
            memo: "SANDBOX A/P bill proof \(proofID)"
        )

        try db.recordBillPayments(
            billIDs: [billID],
            paymentDate: billDate,
            paymentAccountID: paymentAccountID,
            paymentMethod: "Check",
            startingCheckNumber: billCheckNumber,
            memo: "SANDBOX pay bills proof \(proofID)"
        )

        let expenseID = try db.insertExpense(
            vendorNameOverride: "SANDBOX Payee \(proofID)",
            vendorID: vendorID,
            expenseDate: billDate,
            amount: checkAmount,
            accountID: expenseAccountID,
            paymentAccountID: paymentAccountID,
            checkNumber: immediateCheckNumber,
            memo: "SANDBOX immediate check proof \(proofID)"
        )

        appendHarnessLog(
            "sandbox money-out proof token=\(proofID) vendorID=\(vendorID) billID=\(billID) expenseID=\(expenseID) billCheck=\(billCheckNumber) immediateCheck=\(immediateCheckNumber)"
        )
    }

    private func proveBankReconciliationForHarness(token: String) throws {
        let safeToken = token.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24)
        guard !safeToken.isEmpty else {
            throw HarnessDataMutationError.invalidToken
        }
        let proofID = String(safeToken)
        let accountName = "SANDBOX Bank \(proofID)"

        // Dedicated sandbox bank account so the reconciliation row is unambiguous.
        let accountID = try db.insertGLAccount(name: accountName, type: "asset", number: "")

        let statementDate = DateFormatter.isoDate.string(from: Date())
        let checkSuffix = String(proofID.suffix(4))

        // Two checks out (100.00 + 50.00) and one deposit in (400.00) → net +250.00.
        _ = try db.insertExpense(
            vendorNameOverride: "SANDBOX Recon Payee \(proofID)", vendorID: nil,
            expenseDate: statementDate, amount: 100.00,
            accountID: nil, paymentAccountID: accountID,
            checkNumber: "70\(checkSuffix)",
            memo: "SANDBOX recon check \(proofID) A"
        )
        _ = try db.insertExpense(
            vendorNameOverride: "SANDBOX Recon Payee \(proofID)", vendorID: nil,
            expenseDate: statementDate, amount: 50.00,
            accountID: nil, paymentAccountID: accountID,
            checkNumber: "71\(checkSuffix)",
            memo: "SANDBOX recon check \(proofID) B"
        )
        _ = try db.insertDepositRecord(
            depositDate: statementDate, accountID: accountID,
            reference: "SANDBOX-DEP-\(proofID)",
            memo: "SANDBOX recon deposit \(proofID)",
            totalAmount: 400.00
        )

        // Pull the working set and commit clearing all three to a zero difference.
        let items = try db.fetchReconcileItems(
            accountID: accountID,
            accountName: accountName,
            throughDate: statementDate
        )
        let endingBalance = items.reduce(0) { $0 + $1.signedAmount }  // +250.00
        let recon = try db.commitReconciliation(
            existingID: nil,
            accountID: accountID,
            statementDate: statementDate,
            beginningBalance: 0,
            endingBalance: endingBalance,
            clearedItems: items
        )

        appendHarnessLog(
            "sandbox bank-reconciliation proof token=\(proofID) accountID=\(accountID) reconID=\(recon.id) items=\(items.count) ending=\(String(format: "%.2f", endingBalance))"
        )
    }

    private func proveJobCostingForHarness(token: String) throws {
        let safeToken = token.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24)
        guard !safeToken.isEmpty else {
            throw HarnessDataMutationError.invalidToken
        }

        let proofID = String(safeToken)
        let customerID = try db.insertCustomer(
            name: "SANDBOX Job Customer \(proofID)",
            company: "SANDBOX Harness",
            primaryContact: "Renaissance Harness",
            email: "sandbox@example.invalid",
            phone: "",
            address: "Sandbox Only",
            city: "",
            state: "",
            zip: ""
        )
        let jobID = try db.insertJob(
            customerID: customerID,
            name: "SANDBOX Costing Job \(proofID)",
            status: "active",
            siteAddress: "Sandbox Only",
            notes: "SANDBOX job costing proof \(proofID)"
        )
        let vendorID = try db.insertVendor(
            name: "SANDBOX Job Vendor \(proofID)",
            company: "SANDBOX Harness",
            primaryContact: "Renaissance Harness",
            phone: "",
            address: "Sandbox Only",
            ein: "",
            is1099: false,
            isInternalSelf: false
        )

        guard let expenseAccountID = try db.fetchAccounts(type: "expense").first?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }
        guard let paymentAccountID = try db.fetchAccounts(type: "asset").first(where: {
            $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        })?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }

        let formatter = DateFormatter.isoDate
        let issueDate = formatter.string(from: Date())
        let dueDate = formatter.string(from: Date().addingTimeInterval(14 * 86_400))

        let estimateID = try db.saveEstimateWithLines(
            number: "SANDBOX-JOB-EST-\(proofID)",
            customerID: customerID,
            issueDate: issueDate,
            validUntil: dueDate,
            memo: "SANDBOX job costing estimate \(proofID)",
            total: 500,
            status: "accepted",
            lines: [
                (
                    description: "SANDBOX job revenue estimate",
                    quantity: 1,
                    rate: 500,
                    amount: 500
                )
            ],
            jobID: jobID
        )

        let invoiceID = try db.saveInvoiceWithLines(
            number: "SANDBOX-JOB-INV-\(proofID)",
            customerID: customerID,
            issueDate: issueDate,
            dueDate: dueDate,
            memo: "SANDBOX job costing invoice \(proofID)",
            total: 300,
            lines: [
                (
                    description: "SANDBOX job progress invoice",
                    quantity: 1,
                    rate: 300,
                    amount: 300
                )
            ],
            jobID: jobID
        )
        try db.linkEstimateToInvoice(
            estimateID: estimateID,
            invoiceID: invoiceID,
            mode: .percentOfEstimate,
            percentValue: 60,
            shouldMarkEstimateConverted: false,
            sourceNote: "SANDBOX job costing proof \(proofID)"
        )

        _ = try db.recordCustomerPayment(
            customerID: customerID,
            paymentDate: issueDate,
            paymentAmount: 100,
            method: "check",
            reference: "SANDBOX-JOB-PAY-\(proofID)",
            memo: "SANDBOX partial job payment \(proofID)",
            depositAccountID: paymentAccountID,
            cashAllocations: [(invoiceID: invoiceID, amount: 100)],
            creditApplications: []
        )

        let paidBillID = try db.insertBill(
            vendorNameOverride: "SANDBOX Job Vendor \(proofID)",
            vendorID: vendorID,
            billDate: issueDate,
            dueDate: dueDate,
            amount: 120,
            accountID: expenseAccountID,
            jobID: jobID,
            memo: "SANDBOX paid job bill \(proofID)"
        )
        try db.recordBillPayments(
            billIDs: [paidBillID],
            paymentDate: issueDate,
            paymentAccountID: paymentAccountID,
            paymentMethod: "Check",
            startingCheckNumber: "93\(String(proofID.suffix(4)))",
            memo: "SANDBOX paid job bill payment \(proofID)"
        )

        let unpaidBillID = try db.insertBill(
            vendorNameOverride: "SANDBOX Job Vendor \(proofID)",
            vendorID: vendorID,
            billDate: issueDate,
            dueDate: dueDate,
            amount: 80,
            accountID: expenseAccountID,
            jobID: jobID,
            memo: "SANDBOX unpaid job bill \(proofID)"
        )

        let expenseID = try db.insertExpense(
            vendorNameOverride: "SANDBOX Job Vendor \(proofID)",
            vendorID: vendorID,
            expenseDate: issueDate,
            amount: 50,
            accountID: expenseAccountID,
            paymentAccountID: paymentAccountID,
            checkNumber: "94\(String(proofID.suffix(4)))",
            memo: "SANDBOX immediate job expense \(proofID)",
            jobID: jobID
        )

        appendHarnessLog(
            "sandbox job costing proof token=\(proofID) customerID=\(customerID) jobID=\(jobID) vendorID=\(vendorID) estimateID=\(estimateID) invoiceID=\(invoiceID) paidBillID=\(paidBillID) unpaidBillID=\(unpaidBillID) expenseID=\(expenseID)"
        )
    }

    private func proveReportCorrectnessForHarness(token: String) throws {
        let safeToken = token.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24)
        guard !safeToken.isEmpty else {
            throw HarnessDataMutationError.invalidToken
        }

        let proofID = String(safeToken)
        let reportDate = "2099-01-15"
        let customerID = try db.insertCustomer(
            name: "SANDBOX Report Customer \(proofID)",
            company: "SANDBOX Harness",
            primaryContact: "Renaissance Harness",
            email: "sandbox@example.invalid",
            phone: "",
            address: "Sandbox Only",
            city: "",
            state: "",
            zip: ""
        )
        let jobID = try db.insertJob(
            customerID: customerID,
            name: "SANDBOX Report Job \(proofID)",
            status: "active",
            siteAddress: "Sandbox Only",
            notes: "SANDBOX report correctness proof \(proofID)"
        )
        let vendorID = try db.insertVendor(
            name: "SANDBOX Report Vendor \(proofID)",
            company: "SANDBOX Harness",
            primaryContact: "Renaissance Harness",
            phone: "",
            address: "Sandbox Only",
            ein: "",
            is1099: false,
            isInternalSelf: false
        )

        guard let expenseAccountID = try db.fetchAccounts(type: "expense").first?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }
        guard let paymentAccountID = try db.fetchAccounts(type: "asset").first(where: {
            $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        })?.id else {
            throw HarnessDataMutationError.depositAccountMissing
        }

        let estimateID = try db.saveEstimateWithLines(
            number: "SANDBOX-RPT-EST-\(proofID)",
            customerID: customerID,
            issueDate: reportDate,
            validUntil: "2099-02-15",
            memo: "SANDBOX report estimate \(proofID)",
            total: 300,
            status: "accepted",
            lines: [
                (
                    description: "SANDBOX report estimate line",
                    quantity: 1,
                    rate: 300,
                    amount: 300
                )
            ],
            jobID: jobID
        )
        let invoiceID = try db.saveInvoiceWithLines(
            number: "SANDBOX-RPT-INV-\(proofID)",
            customerID: customerID,
            issueDate: reportDate,
            dueDate: "2099-01-30",
            memo: "SANDBOX report invoice \(proofID)",
            total: 225,
            lines: [
                (
                    description: "SANDBOX report invoice line",
                    quantity: 1,
                    rate: 225,
                    amount: 225
                )
            ],
            jobID: jobID
        )
        try db.linkEstimateToInvoice(
            estimateID: estimateID,
            invoiceID: invoiceID,
            mode: .percentOfEstimate,
            percentValue: 75,
            shouldMarkEstimateConverted: false,
            sourceNote: "SANDBOX report correctness proof \(proofID)"
        )
        _ = try db.recordCustomerPayment(
            customerID: customerID,
            paymentDate: reportDate,
            paymentAmount: 150,
            method: "check",
            reference: "SANDBOX-RPT-PAY-\(proofID)",
            memo: "SANDBOX report payment \(proofID)",
            depositAccountID: paymentAccountID,
            cashAllocations: [(invoiceID: invoiceID, amount: 150)],
            creditApplications: []
        )
        let expenseID = try db.insertExpense(
            vendorNameOverride: "SANDBOX Report Vendor \(proofID)",
            vendorID: vendorID,
            expenseDate: reportDate,
            amount: 40,
            accountID: expenseAccountID,
            paymentAccountID: paymentAccountID,
            checkNumber: "95\(String(proofID.suffix(4)))",
            memo: "SANDBOX report expense \(proofID)",
            jobID: jobID
        )

        appendHarnessLog(
            "sandbox report correctness proof token=\(proofID) date=\(reportDate) customerID=\(customerID) jobID=\(jobID) vendorID=\(vendorID) estimateID=\(estimateID) invoiceID=\(invoiceID) expenseID=\(expenseID)"
        )
    }

    private func approveFirstSandboxOrderSheetForHarness() throws {
        guard let orderSheet = try orderSheetStore.fetchOrderSheets(statuses: [.pending, .inReview]).first else {
            appendHarnessLog("sandbox order sheet approval skipped: no pending row")
            return
        }
        guard let customerID = try db.fetchCustomers().first?.id else {
            throw OrderSheetApprovalError.missingCustomer
        }

        let formatter = DateFormatter.isoDate
        let issueDate = formatter.string(from: Date())
        let validUntil = formatter.string(from: Date().addingTimeInterval(30 * 86_400))
        let draft = OrderSheetReviewDraft(
            customerID: customerID,
            issueDate: issueDate,
            validUntil: validUntil,
            memo: "SANDBOX order sheet approval: \(orderSheet.originalFilename)",
            status: "draft",
            lines: [
                OrderSheetDraftLine(
                    itemName: "SANDBOX Intake",
                    description: "SANDBOX order sheet intake test",
                    quantity: "1",
                    rate: "1.00",
                    reviewHint: "Created by sandbox harness approval hook"
                )
            ]
        )

        let originalSettings = orderSheetApprovalSettings
        orderSheetApprovalSettings = OrderSheetApprovalSettings(testingModeEnabled: false, requireConfirmation: false)
        defer { orderSheetApprovalSettings = originalSettings }

        let estimate = try approveOrderSheetToEstimate(orderSheetID: orderSheet.id, draft: draft)
        appendHarnessLog("sandbox approved order sheet id=\(orderSheet.id) estimateID=\(estimate.id) number=\(estimate.number)")
    }

    func clearPendingCustomerID(_ expectedID: Int64? = nil) {
        guard expectedID == nil || pendingCustomerID == expectedID else { return }
        pendingCustomerID = nil
    }

    func peekPendingEstimateID() -> Int64? { pendingEstimateID }

    func clearPendingEstimateID(_ expectedID: Int64? = nil) {
        guard expectedID == nil || pendingEstimateID == expectedID else { return }
        pendingEstimateID = nil
    }

    func peekPendingInvoiceID() -> Int64? { pendingInvoiceID }

    func clearPendingInvoiceID(_ expectedID: Int64? = nil) {
        guard expectedID == nil || pendingInvoiceID == expectedID else { return }
        pendingInvoiceID = nil
    }

    func peekPendingEditEstimateID() -> Int64? { pendingEditEstimateID }

    func clearPendingEditEstimateID(_ expectedID: Int64? = nil) {
        guard expectedID == nil || pendingEditEstimateID == expectedID else { return }
        pendingEditEstimateID = nil
    }

    func peekPendingEditInvoiceID() -> Int64? { pendingEditInvoiceID }

    func clearPendingEditInvoiceID(_ expectedID: Int64? = nil) {
        guard expectedID == nil || pendingEditInvoiceID == expectedID else { return }
        pendingEditInvoiceID = nil
    }

    func consumePendingOpenExpenseID() -> Int64? {
        let pending = pendingOpenExpenseID
        pendingOpenExpenseID = nil
        return pending
    }

    func consumePendingEmailDocumentID() -> Int64? {
        let pending = pendingEmailDocumentID
        pendingEmailDocumentID = nil
        return pending
    }

    func consumePendingOpenWriteCheck() -> Bool {
        let pending = pendingOpenWriteCheck
        pendingOpenWriteCheck = false
        return pending
    }

    func consumePendingReviewFirstOrderSheet() -> Bool {
        let pending = pendingReviewFirstOrderSheet
        pendingReviewFirstOrderSheet = false
        return pending
    }

    func consumePendingPreviewEstimateItemQuery() -> String? {
        let pending = pendingPreviewEstimateItemQuery
        pendingPreviewEstimateItemQuery = nil
        return pending
    }

    func consumePendingPreviewInvoiceItemQuery() -> String? {
        let pending = pendingPreviewInvoiceItemQuery
        pendingPreviewInvoiceItemQuery = nil
        return pending
    }

    func consumePendingPreviewWriteCheckPayeeQuery() -> String? {
        let pending = pendingPreviewWriteCheckPayeeQuery
        pendingPreviewWriteCheckPayeeQuery = nil
        return pending
    }

    func consumePendingPreviewEstimateInvoiceProgressChooser() -> Bool {
        let pending = pendingPreviewEstimateInvoiceProgressChooser
        pendingPreviewEstimateInvoiceProgressChooser = false
        return pending
    }

    func consumePendingVerifyInvoiceManualDescription() -> Bool {
        let pending = pendingVerifyInvoiceManualDescription
        pendingVerifyInvoiceManualDescription = false
        return pending
    }

    func consumePendingEmailEstimateOnOpen() -> Bool {
        let pending = pendingEmailEstimateOnOpen
        pendingEmailEstimateOnOpen = false
        return pending
    }

    func consumePendingEmailInvoiceOnOpen() -> Bool {
        let pending = pendingEmailInvoiceOnOpen
        pendingEmailInvoiceOnOpen = false
        return pending
    }

    static func reportTab(from rawValue: String) -> ReportTab? {
        if let exact = ReportTab.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }) {
            return exact
        }

        switch rawValue.lowercased() {
        case "historical", "historicalpl", "historical_qb_pl", "historical_qb_p&l":
            return .historicalPL
        case "trialbalance", "trial_balance":
            return .trialBalance
        case "historicalcashflows", "historical_cash_flows", "cashflows", "cash_flows":
            return .historicalCashFlows
        case "salesbyitem", "sales_by_item":
            return .salesByItem
        case "operational", "operationalpl", "operational_cash_pl", "operational_cash_summary":
            return .operationalPL
        case "araging", "ar_aging":
            return .arAging
        case "jobprofitability", "job_profitability", "jobs", "jobreport":
            return .jobProfitability
        case "1099", "1099summary", "report1099":
            return .report1099
        case "vendor", "vendorhistory", "vendor_spend", "vendorspend":
            return .vendorHistory
        case "statement", "customerstatement", "customer_statements":
            return .statement
        default:
            return nil
        }
    }

    func refreshMailReview() {
        guard !isRefreshingMailReview else { return }
        guard mailReviewSettings.isEnabled else {
            mailReviewSnapshot = .empty
            return
        }

        isRefreshingMailReview = true
        let settings = mailReviewSettings
        let customers = self.customers

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try MailReviewService.refreshUnreadMessages(
                    settings: settings,
                    customers: customers
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.mailReviewSnapshot = result.snapshot
                    self.isRefreshingMailReview = false
                    self.mailReviewLastError = ""
                    var status = "Mail review refreshed: \(result.snapshot.priorityCount) work unread, \(result.snapshot.likelyJunkCount) likely junk, \(result.snapshot.otherCount) other unread."
                    if result.autoTrashedCount > 0 {
                        status += " Auto-trashed \(result.autoTrashedCount) strong junk message\(result.autoTrashedCount == 1 ? "" : "s")."
                    }
                    if result.autoTrashFailureCount > 0 {
                        status += " \(result.autoTrashFailureCount) junk message\(result.autoTrashFailureCount == 1 ? "" : "s") could not be auto-trashed."
                    }
                    if let diagnostic = result.snapshot.diagnosticMessage, !diagnostic.isEmpty {
                        status += " \(diagnostic)"
                    }
                    self.statusMessage = status
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isRefreshingMailReview = false
                    self.mailReviewLastError = error.localizedDescription
                    self.statusMessage = "Mail review failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func openPreferredMailApp() {
        do {
            try MailReviewService.openPreferredMailApp(using: mailReviewSettings)
            statusMessage = "Opened \(mailReviewSettings.preferredProvider.title)."
        } catch {
            statusMessage = "Could not open Mail: \(error.localizedDescription)"
        }
    }

    func openMailMessage(_ message: MailInboxMessage) {
        do {
            try MailReviewService.openMessage(message)
            statusMessage = message.supportsDirectActions
                ? "Opening \(message.subject) in \(message.provider.title)..."
                : "Opened Mail so you can review \(message.subject) there."
        } catch {
            statusMessage = "Could not open message: \(error.localizedDescription)"
        }
    }

    func searchMailHistory(query: String, since cutoffDate: Date?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearMailHistorySearch()
            return
        }

        guard !isSearchingMailHistory else { return }
        isSearchingMailHistory = true
        let settings = mailReviewSettings

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let results = try MailReviewService.searchMailHistory(
                    using: settings,
                    keyword: trimmedQuery,
                    since: cutoffDate
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isSearchingMailHistory = false
                    self.mailHistorySearchResults = results
                    self.statusMessage = results.isEmpty
                        ? "No mail matched \"\(trimmedQuery)\" in the selected date window."
                        : "Found \(results.count) mail result\(results.count == 1 ? "" : "s") for \"\(trimmedQuery)\"."
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isSearchingMailHistory = false
                    self.mailHistorySearchResults = []
                    self.statusMessage = "Could not search mail history: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearMailHistorySearch() {
        mailHistorySearchResults = []
        isSearchingMailHistory = false
    }

    func loadRecentSentMail(since cutoffDate: Date?) {
        guard !isLoadingRecentSentMail else { return }
        isLoadingRecentSentMail = true
        let settings = mailReviewSettings

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let results = try MailReviewService.fetchRecentSentMessages(
                    using: settings,
                    since: cutoffDate
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoadingRecentSentMail = false
                    self.mailRecentSentMessages = results
                    self.statusMessage = results.isEmpty
                        ? "No sent mail was found in the selected date window."
                        : "Loaded \(results.count) recent sent message\(results.count == 1 ? "" : "s")."
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoadingRecentSentMail = false
                    self.mailRecentSentMessages = []
                    self.statusMessage = "Could not load recent sent mail: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearRecentSentMail() {
        mailRecentSentMessages = []
        isLoadingRecentSentMail = false
    }

    func openMailHistoryMessage(_ message: MailHistoryMessage) {
        do {
            try MailReviewService.openHistoryMessage(message)
            statusMessage = "Opening \(message.subject) in \(message.provider.title)..."
        } catch {
            statusMessage = "Could not open mail result: \(error.localizedDescription)"
        }
    }

    func mailBodyKey(for message: MailInboxMessage) -> String {
        "inbox-\(message.provider.rawValue)-\(message.id)"
    }

    func mailBodyKey(for message: MailHistoryMessage) -> String {
        "history-\(message.provider.rawValue)-\(message.direction.rawValue)-\(message.accountName)-\(message.mailbox)-\(message.id)"
    }

    func loadMailBodyIfNeeded(for message: MailInboxMessage) {
        let bodyKey = mailBodyKey(for: message)
        guard mailBodyCache[bodyKey] == nil else { return }
        guard mailBodyLoadingKey != bodyKey else { return }

        mailBodyLoadingKey = bodyKey
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let body = try MailReviewService.fetchBodyText(for: message)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.mailBodyLoadingKey = self.mailBodyLoadingKey == bodyKey ? nil : self.mailBodyLoadingKey
                    self.mailBodyCache[bodyKey] = body.isEmpty ? "(No body text available)" : body
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.mailBodyLoadingKey = self.mailBodyLoadingKey == bodyKey ? nil : self.mailBodyLoadingKey
                    self.mailBodyCache[bodyKey] = "Could not load body text: \(error.localizedDescription)"
                }
            }
        }
    }

    func loadMailBodyIfNeeded(for message: MailHistoryMessage) {
        let bodyKey = mailBodyKey(for: message)
        guard mailBodyCache[bodyKey] == nil else { return }
        guard mailBodyLoadingKey != bodyKey else { return }

        mailBodyLoadingKey = bodyKey
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let body = try MailReviewService.fetchBodyText(for: message)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.mailBodyLoadingKey = self.mailBodyLoadingKey == bodyKey ? nil : self.mailBodyLoadingKey
                    self.mailBodyCache[bodyKey] = body.isEmpty ? "(No body text available)" : body
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.mailBodyLoadingKey = self.mailBodyLoadingKey == bodyKey ? nil : self.mailBodyLoadingKey
                    self.mailBodyCache[bodyKey] = "Could not load body text: \(error.localizedDescription)"
                }
            }
        }
    }

    func markMailMessageRead(_ message: MailInboxMessage) {
        do {
            try MailReviewService.markMessageRead(message)
            removeMailMessages(withIDs: Set([message.id]))
            statusMessage = "Marked \(message.subject) as read in \(message.provider.title)."
        } catch {
            statusMessage = "Could not mark message read: \(error.localizedDescription)"
        }
    }

    func markAllMailMessagesRead() {
        markMailMessagesRead(mailReviewSnapshot.actionableMessages)
    }

    func markAllMailHistoryRead() {
        guard !isPerformingMailReviewAction else { return }
        isPerformingMailReviewAction = true
        let settings = mailReviewSettings

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let updatedCount = try MailReviewService.markAllUnreadMessagesRead(using: settings)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isPerformingMailReviewAction = false
                    self.mailReviewSnapshot = .empty
                    self.statusMessage = updatedCount > 0
                        ? "Marked \(updatedCount) unread message\(updatedCount == 1 ? "" : "s") as read across your full inbox history."
                        : "There were no unread inbox messages to mark as read."
                    self.refreshMailReview()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isPerformingMailReviewAction = false
                    self.statusMessage = "Could not mark all unread inbox history as read: \(error.localizedDescription)"
                }
            }
        }
    }

    func markMailMessagesRead(_ messages: [MailInboxMessage]) {
        guard !isPerformingMailReviewAction else { return }

        let actionableMessages = messages.filter(\.supportsDirectActions)
        guard !actionableMessages.isEmpty else {
            statusMessage = mailReviewSnapshot.totalUnread > 0
                ? "Mail Center is currently in read-only fallback mode. Open Mail to mark these messages as read."
                : "No unread messages to mark as read."
            return
        }

        isPerformingMailReviewAction = true

        Task.detached(priority: .userInitiated) { [weak self] in
            var markedIDs = Set<Int64>()
            var successCount = 0
            var failureCount = 0

            for message in actionableMessages {
                do {
                    try MailReviewService.markMessageRead(message)
                    markedIDs.insert(message.id)
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }

            let finalizedMarkedIDs = markedIDs
            let finalizedSuccessCount = successCount
            let finalizedFailureCount = failureCount

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isPerformingMailReviewAction = false
                self.removeMailMessages(withIDs: finalizedMarkedIDs)

                if finalizedSuccessCount > 0 && finalizedFailureCount == 0 {
                    self.statusMessage = "Marked \(finalizedSuccessCount) message\(finalizedSuccessCount == 1 ? "" : "s") as read."
                } else if finalizedSuccessCount > 0 {
                    self.statusMessage = "Marked \(finalizedSuccessCount) message\(finalizedSuccessCount == 1 ? "" : "s") as read. \(finalizedFailureCount) could not be updated."
                } else {
                    self.statusMessage = "Could not mark unread messages as read."
                }
            }
        }
    }

    func trashMailMessage(_ message: MailInboxMessage) {
        do {
            try MailReviewService.trashMessage(message)
            removeMailMessages(withIDs: Set([message.id]))
            statusMessage = "Moved \(message.subject) to Trash in \(message.provider.title)."
        } catch {
            statusMessage = "Could not move message to Trash: \(error.localizedDescription)"
        }
    }

    func trashMailMessages(_ messages: [MailInboxMessage]) {
        guard !isPerformingMailReviewAction else { return }

        let actionableMessages = messages.filter(\.supportsDirectActions)
        guard !actionableMessages.isEmpty else {
            statusMessage = "No junk messages are currently available for bulk trash."
            return
        }

        isPerformingMailReviewAction = true

        Task.detached(priority: .userInitiated) { [weak self] in
            var trashedIDs = Set<Int64>()
            var successCount = 0
            var failureCount = 0

            for message in actionableMessages {
                do {
                    try MailReviewService.trashMessage(message)
                    trashedIDs.insert(message.id)
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }

            let finalizedTrashedIDs = trashedIDs
            let finalizedSuccessCount = successCount
            let finalizedFailureCount = failureCount

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isPerformingMailReviewAction = false
                self.removeMailMessages(withIDs: finalizedTrashedIDs)

                if finalizedSuccessCount > 0 && finalizedFailureCount == 0 {
                    self.statusMessage = "Moved \(finalizedSuccessCount) message\(finalizedSuccessCount == 1 ? "" : "s") to Trash."
                } else if finalizedSuccessCount > 0 {
                    self.statusMessage = "Moved \(finalizedSuccessCount) message\(finalizedSuccessCount == 1 ? "" : "s") to Trash. \(finalizedFailureCount) could not be moved."
                } else {
                    self.statusMessage = "Could not move junk messages to Trash."
                }
            }
        }
    }

    func clearMailJunkFolder() {
        guard !isPerformingMailReviewAction else { return }
        isPerformingMailReviewAction = true
        let settings = mailReviewSettings

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let clearedCount = try MailReviewService.clearJunkFolder(using: settings)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isPerformingMailReviewAction = false
                    self.statusMessage = clearedCount > 0
                        ? "Cleared \(clearedCount) message\(clearedCount == 1 ? "" : "s") from junk folders across your full mail history."
                        : "Junk folders were already empty."
                    self.refreshMailReview()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isPerformingMailReviewAction = false
                    self.statusMessage = "Could not clear the junk folder: \(error.localizedDescription)"
                }
            }
        }
    }

    private func removeMailMessages(withIDs ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        mailReviewSnapshot.priorityMessages.removeAll { ids.contains($0.id) }
        mailReviewSnapshot.likelyJunkMessages.removeAll { ids.contains($0.id) }
        mailReviewSnapshot.otherMessages.removeAll { ids.contains($0.id) }
    }

    func saveMailReviewSettings(_ settings: MailReviewSettings) {
        mailReviewSettings = settings
        settings.save()
        if settings.isEnabled && settings.autoRefreshOnLaunch {
            refreshMailReview()
        } else if !settings.isEnabled {
            mailReviewSnapshot = .empty
            mailReviewLastError = ""
        }
    }

    func saveOldQBSyncSettings(_ settings: OldQBSyncSettings) {
        oldQBSyncSettings = settings
        settings.save()
    }

    func noteOldQBSyncPreparedOffline() {
        oldQBSyncSnapshot.lastResultSummary = "Sync Center is staged in the app. Live old-Mac verification is the next step once both Macs are on."
    }

    // MARK: - Native Data Entry

    func refreshCustomers() {
        do { customers = try db.fetchCustomers() }
        catch { statusMessage = "Failed loading customers: \(error.localizedDescription)" }
    }

    func refreshJobs() {
        do { jobs = try db.fetchJobs(includeInactive: true) }
        catch { statusMessage = "Failed loading jobs: \(error.localizedDescription)" }
    }

    func refreshVendors() {
        do { vendors = try db.fetchVendors() }
        catch { statusMessage = "Failed loading vendors: \(error.localizedDescription)" }
    }

    func refreshAccounts() {
        do { accounts = try db.fetchAccounts() }
        catch { statusMessage = "Failed loading accounts: \(error.localizedDescription)" }
    }

    func refreshPaymentTerms() {
        do { paymentTerms = try db.fetchPaymentTerms() }
        catch { statusMessage = "Failed loading payment terms: \(error.localizedDescription)" }
    }

    func refreshPaymentMethods() {
        do { paymentMethods = try db.fetchPaymentMethods() }
        catch { statusMessage = "Failed loading payment methods: \(error.localizedDescription)" }
    }

    func refreshEstimates() {
        do { estimates = try db.fetchEstimates() }
        catch { statusMessage = "Failed loading estimates: \(error.localizedDescription)" }
    }

    func refreshNativeInvoices() {
        do { nativeInvoices = try db.fetchNativeInvoices() }
        catch { statusMessage = "Failed loading invoices: \(error.localizedDescription)" }
    }

    func refreshSalesReceipts() {
        do { salesReceipts = try db.fetchSalesReceipts() }
        catch { statusMessage = "Failed loading sales receipts: \(error.localizedDescription)" }
    }

    func refreshExpenses() {
        do { expenses = try db.fetchExpenses() }
        catch { statusMessage = "Failed loading expenses: \(error.localizedDescription)" }
    }

    func refreshServiceItems() {
        do { serviceItems = try db.fetchServiceItems() }
        catch { statusMessage = "Failed loading service items: \(error.localizedDescription)" }
    }

    func nextInvoiceNumber() -> String {
        (try? db.nextInvoiceNumber()) ?? "INV-001"
    }

    func nextSalesReceiptNumber() -> String {
        (try? db.nextSalesReceiptNumber()) ?? "SR-001"
    }

    func nextEstimateNumber() -> String {
        (try? db.nextEstimateNumber()) ?? "EST-001"
    }

    func nextCheckNumber(paymentAccountID: Int64) -> String {
        (try? db.nextCheckNumber(paymentAccountID: paymentAccountID == 0 ? nil : paymentAccountID)) ?? "1001"
    }

    func refreshOrderSheets() {
        do {
            orderSheets = try orderSheetStore.fetchOrderSheets(statuses: [.pending, .inReview])
        } catch {
            statusMessage = "Failed loading order sheets: \(error.localizedDescription)"
        }
    }

    func fetchLinkedOrderSheets(estimateID: Int64) -> [OrderSheetRow] {
        (try? orderSheetStore.fetchOrderSheets(linkedEstimateID: estimateID)) ?? []
    }

    func openOrderSheetImage(_ row: OrderSheetRow) {
        guard FileManager.default.fileExists(atPath: row.storedPath) else {
            statusMessage = "Order sheet file not found: \(row.originalFilename)"
            return
        }
        NSWorkspace.shared.open(row.imageURL)
    }

    func importOrderSheetPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Select one or more order sheet images to stage for review."
        panel.allowedContentTypes = OrderSheetInboxMonitor.supportedContentTypes

        guard panel.runModal() == .OK else { return }
        processImportedOrderSheets(imageURLs: panel.urls)
    }

    func processImportedOrderSheets(imageURLs: [URL]) {
        let validURLs = imageURLs.filter { !$0.path.isEmpty }
        guard !validURLs.isEmpty else { return }

        isImportingOrderSheets = true
        statusMessage = "Importing \(validURLs.count) order sheet(s)..."

        DispatchQueue.global(qos: .userInitiated).async {
            var imported = 0
            var restaged = 0
            var duplicates = 0

            do {
                let store = OrderSheetStagingStore.newWorker()
                for url in validURLs {
                    switch try store.importOrderSheet(imageURL: url) {
                    case .imported:
                        imported += 1
                    case .restaged:
                        restaged += 1
                    case .duplicate:
                        duplicates += 1
                    }
                }

                DispatchQueue.main.async {
                    self.isImportingOrderSheets = false
                    self.refreshOrderSheets()
                    var parts: [String] = []
                    if imported > 0 {
                        parts.append("staged \(imported) new order sheet\(imported == 1 ? "" : "s")")
                    }
                    if restaged > 0 {
                        parts.append("reopened \(restaged) previously dismissed sheet\(restaged == 1 ? "" : "s")")
                    }
                    if duplicates > 0 {
                        parts.append("skipped \(duplicates) duplicate\(duplicates == 1 ? "" : "s")")
                    }
                    self.statusMessage = parts.isEmpty
                        ? "No new order sheets staged."
                        : parts.map { part in
                            guard let first = part.first else { return part }
                            return String(first).uppercased() + String(part.dropFirst())
                        }.joined(separator: ". ") + "."
                }
            } catch {
                DispatchQueue.main.async {
                    self.isImportingOrderSheets = false
                    self.refreshOrderSheets()
                    self.statusMessage = "Order sheet import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func markOrderSheetInReview(id: Int64) {
        do {
            try orderSheetStore.updateStatus(id: id, status: .inReview)
            refreshOrderSheets()
        } catch {
            statusMessage = "Failed updating order sheet status: \(error.localizedDescription)"
        }
    }

    func saveOrderSheetDraft(orderSheetID: Int64, draft: OrderSheetReviewDraft, status: OrderSheetStatus = .inReview) throws {
        try orderSheetStore.saveReviewDraft(id: orderSheetID, draft: draft, status: status)
        refreshOrderSheets()
    }

    func discardOrderSheet(orderSheetID: Int64, draft: OrderSheetReviewDraft? = nil) throws {
        let row = try orderSheetStore.fetchOrderSheet(id: orderSheetID)
        try orderSheetStore.discardOrderSheet(id: orderSheetID, draft: draft)
        if let row {
            try? OrderSheetInboxMonitor.deleteMatchingSourceFiles(for: row, settings: orderSheetInboxSettings)
        }
        refreshOrderSheets()
    }

    func saveOrderSheetOCR(orderSheetID: Int64, ocrLines: [OrderSheetOCRLine]) throws {
        try orderSheetStore.saveOCRLines(id: orderSheetID, ocrLines: ocrLines)
        refreshOrderSheets()
    }

    @discardableResult
    func approveOrderSheetToEstimate(orderSheetID: Int64, draft: OrderSheetReviewDraft) throws -> (id: Int64, number: String) {
        guard !orderSheetApprovalSettings.testingModeEnabled else {
            throw OrderSheetApprovalError.testingModeEnabled
        }
        guard let customerID = draft.customerID, customerID != 0 else {
            throw OrderSheetApprovalError.missingCustomer
        }

        let payload = draft.lines
            .filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount > 0 }
            .map {
                (
                    description: $0.description,
                    quantity: Double($0.quantity) ?? 1,
                    rate: Double($0.rate) ?? 0,
                    amount: $0.amount
                )
            }
        guard !payload.isEmpty else {
            throw OrderSheetApprovalError.missingLines
        }

        let estimateNumber = try db.nextEstimateNumber()
        let estimateID = try db.saveEstimateWithLines(
            number: estimateNumber,
            customerID: customerID,
            issueDate: draft.issueDate,
            validUntil: draft.validUntil,
            memo: draft.memo,
            total: payload.reduce(0) { $0 + $1.amount },
            status: draft.status,
            lines: payload
        )
        try orderSheetStore.markConverted(id: orderSheetID, linkedEstimateID: estimateID, draft: draft)
        refreshEstimates()
        refreshOrderSheets()
        return (estimateID, estimateNumber)
    }

    func saveOrderSheetApprovalSettings(_ settings: OrderSheetApprovalSettings) {
        settings.save()
        orderSheetApprovalSettings = settings
    }

    func saveOrderSheetInboxSettings(_ settings: OrderSheetInboxSettings) throws {
        let normalized = OrderSheetInboxSettings(
            isEnabled: settings.isEnabled,
            folderPath: settings.folderURL.path,
            scanIntervalSeconds: max(OrderSheetInboxSettings.minimumScanInterval, settings.scanIntervalSeconds),
            deleteAfterStage: settings.deleteAfterStage
        )
        try OrderSheetInboxSettings.ensureDirectory(at: normalized.folderURL)
        normalized.save()
        orderSheetInboxSettings = normalized
        configureOrderSheetInboxMonitoring()
    }

    @discardableResult
    func useRecommendedOrderSheetInboxFolder() throws -> URL {
        let url = try OrderSheetInboxSettings.ensureRecommendedFolderExists()
        var settings = orderSheetInboxSettings
        settings.folderPath = url.path
        settings.isEnabled = true
        try saveOrderSheetInboxSettings(settings)
        return url
    }

    func chooseOrderSheetInboxFolder() -> URL? {
        OrderSheetInboxSettings.chooseFolder(startingAt: orderSheetInboxSettings.folderURL)
    }

    func openOrderSheetInboxFolder() {
        let url = orderSheetInboxSettings.folderURL
        do {
            try OrderSheetInboxSettings.ensureDirectory(at: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            statusMessage = "Could not open order sheet inbox: \(error.localizedDescription)"
        }
    }

    func scanOrderSheetInboxNow() {
        scanOrderSheetInbox(manual: true)
    }

    func scanOrderSheetInboxForReview() {
        scanOrderSheetInbox(manual: false)
    }

    private func configureOrderSheetInboxMonitoring() {
        orderSheetInboxTimer?.invalidate()
        orderSheetInboxTimer = nil

        guard orderSheetInboxSettings.isEnabled else { return }

        let interval = max(OrderSheetInboxSettings.minimumScanInterval, orderSheetInboxSettings.scanIntervalSeconds)
        orderSheetInboxTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanOrderSheetInbox(manual: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                self.scanOrderSheetInbox(manual: false)
            }
        }
    }

    private func scanOrderSheetInbox(manual: Bool) {
        guard !isScanningOrderSheetInbox else { return }
        guard orderSheetInboxSettings.isEnabled else {
            if manual {
                statusMessage = "Phone order sheet inbox is turned off."
            }
            return
        }

        isScanningOrderSheetInbox = true
        let settings = orderSheetInboxSettings
        DispatchQueue.global(qos: .utility).async {
            do {
                let result = try OrderSheetInboxMonitor.scan(settings: settings)
                DispatchQueue.main.async {
                    self.isScanningOrderSheetInbox = false
                    self.refreshOrderSheets()
                    let message = result.statusMessage(manual: manual)
                    if !message.isEmpty {
                        self.statusMessage = message
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isScanningOrderSheetInbox = false
                    if manual {
                        self.statusMessage = "Phone order sheet scan failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func refreshBills() {
        do { bills = try db.fetchBills() }
        catch { statusMessage = "Failed loading bills: \(error.localizedDescription)" }
    }

    func refreshCompanyInfo() {
        do { companyInfo = try db.fetchCompanyInfo() }
        catch { statusMessage = "Failed loading company info: \(error.localizedDescription)" }
    }

    func saveCompanyInfo(_ info: CompanyInfo) {
        do {
            try db.saveCompanyInfo(info)
            companyInfo = info
        } catch {
            statusMessage = "Failed saving company info: \(error.localizedDescription)"
        }
    }

    func addCustomer(name: String, company: String, primaryContact: String, email: String, phone: String,
                     address: String, city: String, state: String, zip: String) {
        do {
            try db.insertCustomer(name: name, company: company, primaryContact: primaryContact, email: email, phone: phone,
                                  address: address, city: city, state: state, zip: zip)
            refreshCustomers()
        } catch {
            statusMessage = "Failed adding customer: \(error.localizedDescription)"
        }
    }

    func updateCustomer(id: Int64, name: String, company: String, primaryContact: String, email: String, phone: String,
                        address: String, city: String, state: String, zip: String) {
        do {
            try db.updateCustomer(id: id, name: name, company: company, primaryContact: primaryContact, email: email, phone: phone,
                                  address: address, city: city, state: state, zip: zip)
            refreshCustomers()
        } catch {
            statusMessage = "Failed updating customer: \(error.localizedDescription)"
        }
    }

    func updateExpense(id: Int64, vendorNameOverride: String, vendorID: Int64?,
                       expenseDate: String, amount: Double,
                       accountID: Int64?, paymentAccountID: Int64?,
                       checkNumber: String, memo: String) {
        do {
            try db.updateExpense(id: id, vendorNameOverride: vendorNameOverride, vendorID: vendorID,
                                 expenseDate: expenseDate, amount: amount, accountID: accountID,
                                 paymentAccountID: paymentAccountID, checkNumber: checkNumber, memo: memo)
            refreshExpenses()
        } catch {
            statusMessage = "Failed updating expense: \(error.localizedDescription)"
        }
    }

    func deleteExpense(id: Int64) {
        do {
            try db.deleteExpense(id: id)
            refreshExpenses()
        } catch {
            statusMessage = "Failed deleting expense: \(error.localizedDescription)"
        }
    }

    func addVendor(name: String, company: String, primaryContact: String, phone: String, address: String, ein: String, is1099: Bool, isInternalSelf: Bool) {
        do {
            try db.insertVendor(name: name, company: company, primaryContact: primaryContact, phone: phone, address: address, ein: ein, is1099: is1099, isInternalSelf: isInternalSelf)
            refreshVendors()
        } catch {
            statusMessage = "Failed adding vendor: \(error.localizedDescription)"
        }
    }

    func updateVendor(id: Int64, name: String, company: String, primaryContact: String, phone: String, address: String, ein: String, is1099: Bool, isInternalSelf: Bool) {
        do {
            try db.updateVendor(id: id, name: name, company: company, primaryContact: primaryContact, phone: phone, address: address, ein: ein, is1099: is1099, isInternalSelf: isInternalSelf)
            refreshVendors()
        } catch {
            statusMessage = "Failed updating vendor: \(error.localizedDescription)"
        }
    }

    func refreshImportSessions() {
        do {
            importSessions = try db.fetchImportSessions()
        } catch {
            statusMessage = "Failed loading import sessions: \(error.localizedDescription)"
        }
    }

    func refreshTransactions() {
        do {
            transactions = try db.fetchTransactions(search: transactionSearch)
        } catch {
            statusMessage = "Failed loading transactions: \(error.localizedDescription)"
        }
    }

    func refreshInvoices() {
        do {
            invoices = try db.fetchInvoices(search: invoiceSearch)
        } catch {
            statusMessage = "Failed loading invoices: \(error.localizedDescription)"
        }
    }

    func refreshPayouts() {
        do {
            payouts = try db.fetchPayouts(search: payoutSearch)
        } catch {
            statusMessage = "Failed loading payouts: \(error.localizedDescription)"
        }
    }

    func refreshDocuments() {
        do {
            documents = try db.fetchDocuments(search: documentSearch)
            warmDocumentReadabilityCacheIfNeeded(rows: documents)
        } catch {
            statusMessage = "Failed loading documents: \(error.localizedDescription)"
        }
    }

    func refreshIssues() {
        do {
            issues = try db.fetchIssues()
        } catch {
            statusMessage = "Failed loading issues: \(error.localizedDescription)"
        }
    }

    func resolvedDocumentURL(for row: DocumentRow) -> URL? {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: row.sourcePath)
        let storedURL = URL(fileURLWithPath: row.storedPath)
        let candidateURLs = [storedURL, sourceURL]
        guard let documentURL = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }
        guard documentURL.pathExtension.lowercased() == "pdf" else {
            return documentURL
        }
        return (try? PDFDocumentNormalizer.normalizedURLIfNeeded(for: documentURL)) ?? documentURL
    }

    func openDocument(_ row: DocumentRow) {
        guard let documentURL = resolvedDocumentURL(for: row) else {
            statusMessage = "Document file not found: \(row.relativePath)"
            return
        }

        NSWorkspace.shared.open(documentURL)
    }

    func emailDocument(_ row: DocumentRow) {
        guard let documentURL = resolvedDocumentURL(for: row) else {
            statusMessage = "Document file not found: \(row.relativePath)"
            return
        }

        do {
            try FileShareService.emailFile(
                fileURL: documentURL,
                subject: "Renaissance Filed document: \(row.documentFileName)"
            )
            statusMessage = "Opening Mail for \(row.documentFileName)..."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func warmDocumentReadabilityCacheIfNeeded(rows: [DocumentRow]) {
        guard !isWarmingDocumentReadabilityCache else { return }
        let fileManager = FileManager.default
        let pdfPaths = rows.compactMap { row -> String? in
            let storedURL = URL(fileURLWithPath: row.storedPath)
            let sourceURL = URL(fileURLWithPath: row.sourcePath)
            guard let documentURL = [storedURL, sourceURL].first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                return nil
            }
            guard documentURL.pathExtension.lowercased() == "pdf" else {
                return nil
            }
            return documentURL.path
        }
        guard !pdfPaths.isEmpty else { return }

        isWarmingDocumentReadabilityCache = true
        DispatchQueue.global(qos: .utility).async {
            defer {
                DispatchQueue.main.async {
                    self.isWarmingDocumentReadabilityCache = false
                }
            }

            for path in pdfPaths {
                _ = try? PDFDocumentNormalizer.normalizedURLIfNeeded(for: URL(fileURLWithPath: path))
            }
        }
    }

    private func importFromFolder(_ url: URL) {
        isImporting = true
        statusMessage = "Importing from \(url.path)..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let importService = ImportService(database: SQLiteDatabase.shared)
                let summary = try importService.importTransferFolder(selectedURL: url)
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.statusMessage =
                        "Import complete. Docs: \(summary.importedDocuments), Transactions: \(summary.importedTransactions), Invoices: \(summary.importedInvoices), Payouts: \(summary.importedPayouts), Issues: \(summary.issues)"
                    self.refreshAll()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.statusMessage = "Import failed: \(error.localizedDescription)"
                    self.refreshAll()
                }
            }
        }
    }
}
