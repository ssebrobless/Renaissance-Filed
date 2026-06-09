import Foundation

struct CustomerRow: Identifiable {
    let id: Int64
    let name: String
    let company: String
    let primaryContact: String
    let email: String
    let phone: String
    let address: String
    let city: String
    let state: String
    let zip: String
    let createdAt: String
    var displayName: String { userFacingEntityName(name) }
    var displayDetail: String? { userFacingEntityDetail(name) }
    var displayLabel: String { userFacingEntityLabel(name) }
}

struct JobRow: Identifiable, Hashable {
    let id: Int64
    let customerID: Int64
    let customerName: String
    let name: String
    let status: String
    let siteAddress: String
    let notes: String
    let isActive: Bool
    let createdAt: String
    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Job" : name }
    var displayCustomerName: String { userFacingEntityName(customerName) }
    var displayLabel: String {
        let customer = displayCustomerName
        return customer.isEmpty ? displayName : "\(displayName) - \(customer)"
    }
    var displayNotes: String { userFacingMemo(notes) }
}

struct VendorRow: Identifiable {
    let id: Int64
    let name: String
    let company: String
    let primaryContact: String
    let phone: String
    let address: String
    let ein: String
    let is1099: Bool
    let isInternalSelf: Bool
    let createdAt: String
    var displayName: String { userFacingEntityName(name) }
    var displayDetail: String? { userFacingEntityDetail(name) }
    var displayLabel: String { userFacingEntityLabel(name) }
}

struct ServiceItemRow: Identifiable {
    let id: Int64
    let name: String
    let description: String
    let incomeAccountID: Int64
    let unitPrice: Double
}

struct AccountRow: Identifiable {
    let id: Int64
    let name: String
    let type: String
    let number: String
}

struct PaymentTermRow: Identifiable {
    let id: Int64
    let name: String
    let refnum: String
    let dueDays: Int
    let minDays: Int
    let discountPercent: Double
    let discountDays: Int
    let termsType: String
}

struct PaymentMethodRow: Identifiable {
    let id: Int64
    let name: String
    let refnum: String
}

struct NativeInvoiceRow: Identifiable, Hashable {
    let id: Int64
    let invoiceNumber: String
    let customerID: Int64
    let customerName: String
    let customerNameOverride: String
    let jobID: Int64
    let jobName: String
    let issueDate: String
    let dueDate: String
    let memo: String
    let status: String
    let total: Double
    let paid: Double
    var balance: Double { total - paid }
    var displayMemo: String { userFacingMemo(memo) }
    var customerDisplayName: String {
        let trimmed = customerNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return userFacingEntityName(customerName)
    }
    var customerDisplayDetail: String? { userFacingEntityDetail(customerName) }
    var customerDisplayLabel: String { userFacingEntityLabel(customerName) }
    var hasJob: Bool { jobID != 0 && !jobName.isEmpty }
}

struct SalesReceiptRow: Identifiable, Hashable {
    let id: Int64
    let receiptNumber: String
    let customerID: Int64
    let customerName: String
    let jobID: Int64
    let jobName: String
    let receiptDate: String
    let memo: String
    let total: Double
    let paymentMethodID: Int64
    let paymentMethodName: String
    let depositAccountID: Int64
    let depositAccountName: String
    let paymentID: Int64

    var displayMemo: String { userFacingMemo(memo) }
    var customerDisplayName: String {
        let normalized = userFacingEntityName(customerName)
        return normalized.isEmpty ? "Walk-in Sale" : normalized
    }
    var customerDisplayDetail: String? { userFacingEntityDetail(customerName) }
    var customerDisplayLabel: String { userFacingEntityLabel(customerName) }
    var hasCustomer: Bool { customerID != 0 && !customerName.isEmpty }
    var hasJob: Bool { jobID != 0 && !jobName.isEmpty }
    var paymentMethodLabel: String { paymentMethodName.isEmpty ? "Undesignated" : paymentMethodName }
    var depositAccountLabel: String { depositAccountName.isEmpty ? "Undeposited Funds" : depositAccountName }
    var depositRouteLabel: String {
        depositAccountID == 0 ? "Hold for bank deposit" : "Direct to \(depositAccountLabel)"
    }
}

struct EstimateRow: Identifiable, Hashable {
    let id: Int64
    let estimateNumber: String
    let customerID: Int64
    let customerName: String
    let customerNameOverride: String
    let jobID: Int64
    let jobName: String
    let issueDate: String
    let validUntil: String
    let memo: String
    let status: String
    let total: Double
    let linkedInvoiceID: Int64
    var displayMemo: String { userFacingMemo(memo) }
    var customerDisplayName: String {
        let trimmed = customerNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return userFacingEntityName(customerName)
    }
    var customerDisplayDetail: String? { userFacingEntityDetail(customerName) }
    var customerDisplayLabel: String { userFacingEntityLabel(customerName) }
    var hasJob: Bool { jobID != 0 && !jobName.isEmpty }
}

struct EstimateRevisionLinkRow: Identifiable, Hashable {
    let id: Int64
    let sourceEstimateID: Int64
    let childEstimateID: Int64
    let createdAt: String
    let relationship: String
    let sourceNote: String
    let estimate: EstimateRow
}

enum EstimateInvoiceProgressMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case fullRemaining
    case percentOfEstimate
    case selectedLines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullRemaining:
            return "Full Remaining Amount"
        case .percentOfEstimate:
            return "Percentage of Estimate"
        case .selectedLines:
            return "Selected Lines Only"
        }
    }

    var shortLabel: String {
        switch self {
        case .fullRemaining:
            return "Full"
        case .percentOfEstimate:
            return "Percent"
        case .selectedLines:
            return "Lines"
        }
    }
}

struct EstimateInvoiceProgressSelection: Hashable {
    var mode: EstimateInvoiceProgressMode = .fullRemaining
    var percentValue: Double = 100
    var selectedEstimateLineIDs: Set<Int64> = []

    var percentDisplayValue: String {
        let rounded = percentValue.rounded()
        if abs(rounded - percentValue) < 0.0001 {
            return String(Int(rounded))
        }
        return String(format: "%.2f", percentValue)
    }
}

struct EstimateProgressSnapshot: Hashable {
    let estimateID: Int64
    let estimateTotal: Double
    let linkedInvoiceCount: Int
    let latestInvoiceID: Int64
    let invoicedTotal: Double

    var remainingTotal: Double {
        max(0, estimateTotal - invoicedTotal)
    }

    var hasRemainingBalance: Bool {
        remainingTotal > 0.01
    }

    static func empty(estimateID: Int64, estimateTotal: Double) -> EstimateProgressSnapshot {
        EstimateProgressSnapshot(
            estimateID: estimateID,
            estimateTotal: estimateTotal,
            linkedInvoiceCount: 0,
            latestInvoiceID: 0,
            invoicedTotal: 0
        )
    }
}

struct EstimateRemainingLineDraft: Identifiable, Hashable {
    let id: String
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
}

struct InvoiceLineEntry: Identifiable {
    var id = UUID()
    var selectedItemID: Int64 = 0
    var itemName: String = ""
    var description: String = ""
    var quantity: String = "1"
    var rate: String = ""
    var reviewHint: String = ""
    var isDescriptionManuallyEdited = false
    var isRateManuallyEdited = false
    var amount: Double {
        let q = Double(quantity) ?? 1
        let r = Double(rate) ?? 0
        return q * r
    }

    init(
        id: UUID = UUID(),
        selectedItemID: Int64 = 0,
        itemName: String = "",
        description: String = "",
        quantity: String = "1",
        rate: String = "",
        reviewHint: String = "",
        isDescriptionManuallyEdited: Bool = false,
        isRateManuallyEdited: Bool = false
    ) {
        self.id = id
        self.selectedItemID = selectedItemID
        self.itemName = itemName
        self.description = description
        self.quantity = quantity
        self.rate = rate
        self.reviewHint = reviewHint
        self.isDescriptionManuallyEdited = isDescriptionManuallyEdited
        self.isRateManuallyEdited = isRateManuallyEdited
    }

    mutating func markDescriptionEdited(byUser value: String) {
        description = value
        isDescriptionManuallyEdited = true
    }

    mutating func markRateEdited(byUser value: String) {
        rate = value
        isRateManuallyEdited = true
    }

    mutating func applyItemDefaults(itemName: String, defaultDescription: String, defaultRate: Double?) {
        self.itemName = itemName
        if !isDescriptionManuallyEdited {
            description = defaultDescription
        }
        if let defaultRate, defaultRate > 0, !isRateManuallyEdited {
            rate = String(format: "%.2f", defaultRate)
        }
    }
}

struct InvoiceLineRow: Identifiable {
    let id: Int64
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
}

struct SalesReceiptLineRow: Identifiable {
    let id: Int64
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
}

struct EstimateLineRow: Identifiable {
    let id: Int64
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
}

struct PaymentDetailRow: Identifiable {
    let id: Int64
    let paymentDate: String
    let amount: Double
    let method: String
    let reference: String
    let memo: String
    var displayMemo: String { userFacingMemo(memo) }
}

struct CreditApplicationDetailRow: Identifiable {
    let id: Int64
    let appliedDate: String
    let amount: Double
    let reference: String
    let memo: String
    let creditType: String
    var displayMemo: String { userFacingMemo(memo) }
}

struct ExpenseRow: Identifiable {
    let id: Int64
    let vendorID: Int64
    let vendorName: String
    let jobID: Int64
    let jobName: String
    let expenseDate: String
    let amount: Double
    let accountName: String
    let accountID: Int64
    let paymentAccountID: Int64
    let paymentAccountName: String
    let checkNumber: String
    let memo: String
    var cleared: Bool = false
    var displayVendorName: String { userFacingEntityName(vendorName) }
    var displayVendorDetail: String? { userFacingEntityDetail(vendorName) }
    var displayMemo: String { userFacingMemo(memo) }
    var hasJob: Bool { jobID != 0 && !jobName.isEmpty }
}

struct CheckDraft {
    let payeeName: String
    let checkNumber: String
    let expenseDate: String
    let amount: Double
    let memo: String
    let categoryName: String
    let bankAccountName: String
    let detailSummary: String
    let itemLines: [CheckItemDraft]

    init(
        payeeName: String,
        checkNumber: String,
        expenseDate: String,
        amount: Double,
        memo: String,
        categoryName: String,
        bankAccountName: String,
        detailSummary: String = "",
        itemLines: [CheckItemDraft] = []
    ) {
        self.payeeName = payeeName
        self.checkNumber = checkNumber
        self.expenseDate = expenseDate
        self.amount = amount
        self.memo = memo
        self.categoryName = categoryName
        self.bankAccountName = bankAccountName
        self.detailSummary = detailSummary
        self.itemLines = itemLines
    }
}

enum CheckCodingMode: String, CaseIterable, Identifiable, Codable {
    case category
    case items

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: return "Category"
        case .items: return "Items"
        }
    }
}

struct CheckItemEntry: Identifiable {
    var id = UUID()
    var selectedItemID: Int64 = 0
    var itemName: String = ""
    var description: String = ""
    var quantity: String = "1"
    var rate: String = ""

    var amount: Double {
        let q = Double(quantity) ?? 1
        let r = Double(rate) ?? 0
        return q * r
    }

    init(
        id: UUID = UUID(),
        selectedItemID: Int64 = 0,
        itemName: String = "",
        description: String = "",
        quantity: String = "1",
        rate: String = ""
    ) {
        self.id = id
        self.selectedItemID = selectedItemID
        self.itemName = itemName
        self.description = description
        self.quantity = quantity
        self.rate = rate
    }

    mutating func applyItemDefaults(itemID: Int64, itemName: String, defaultDescription: String, defaultRate: Double?) {
        selectedItemID = itemID
        self.itemName = itemName
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            description = defaultDescription
        }
        if let defaultRate, defaultRate > 0, rate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rate = String(format: "%.2f", defaultRate)
        }
    }
}

struct CheckItemDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    let serviceItemID: Int64
    let itemName: String
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
}

struct ExpenseCheckItemLineRow: Identifiable {
    let id: Int64
    let serviceItemID: Int64
    let itemName: String
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
}

struct PaymentReceivedRow: Identifiable {
    let id: Int64
    let customerName: String
    let invoiceNumber: String
    let paymentDate: String
    let amount: Double
    let method: String
    let reference: String
    var customerDisplayName: String { userFacingEntityName(customerName) }
    var customerDisplayDetail: String? { userFacingEntityDetail(customerName) }
}

struct DepositRecordRow: Identifiable {
    let id: Int64
    let depositDate: String
    let accountName: String
    let reference: String
    let memo: String
    let totalAmount: Double
}

struct CustomerCreditRow: Identifiable, Hashable {
    let id: Int64
    let customerID: Int64
    let creditDate: String
    let reference: String
    let creditType: String
    let amount: Double
    let remainingAmount: Double
    let memo: String
    var displayMemo: String { userFacingMemo(memo) }
}

struct PLReportLine: Identifiable {
    let id = UUID()
    let label: String
    let total: Double
}

struct PLReport {
    let fromDate: String
    let toDate: String
    let incomeLines: [PLReportLine]
    let expenseLines: [PLReportLine]
    var totalIncome: Double { incomeLines.reduce(0) { $0 + $1.total } }
    var totalExpenses: Double { expenseLines.reduce(0) { $0 + $1.total } }
    var netIncome: Double { totalIncome - totalExpenses }
}

struct HistoricalPLReport {
    let year: Int
    let incomeLines: [PLReportLine]
    let cogsLines: [PLReportLine]
    let expenseLines: [PLReportLine]
    var totalIncome: Double { incomeLines.reduce(0) { $0 + $1.total } }
    var totalCOGS: Double { cogsLines.reduce(0) { $0 + $1.total } }
    var grossProfit: Double { totalIncome - totalCOGS }
    var totalExpenses: Double { expenseLines.reduce(0) { $0 + $1.total } }
    var netIncome: Double { grossProfit - totalExpenses }
}

struct TrialBalanceLine: Identifiable {
    let id = UUID()
    let accountName: String
    let debit: Double
    let credit: Double
}

struct HistoricalTrialBalanceReport {
    let asOfLabel: String
    let sourceName: String
    let lines: [TrialBalanceLine]
    var totalDebit: Double { lines.reduce(0) { $0 + $1.debit } }
    var totalCredit: Double { lines.reduce(0) { $0 + $1.credit } }
}

struct HistoricalCashFlowLine: Identifiable {
    let id = UUID()
    let label: String
    let total: Double
}

struct HistoricalCashFlowSection: Identifiable {
    let id = UUID()
    let title: String
    let lines: [HistoricalCashFlowLine]
}

struct HistoricalCashFlowReport {
    let asOfLabel: String
    let sourceName: String
    let sections: [HistoricalCashFlowSection]
}

struct HistoricalSalesByItemLine: Identifiable {
    let id = UUID()
    let itemName: String
    let quantity: Double
    let amount: Double
    let percentOfSales: Double
    let averagePrice: Double
    let isSubtotal: Bool
}

struct HistoricalSalesByItemSection: Identifiable {
    let id = UUID()
    let title: String
    let lines: [HistoricalSalesByItemLine]
}

struct HistoricalSalesByItemReport {
    let periodLabel: String
    let sourceName: String
    let sections: [HistoricalSalesByItemSection]
}

struct ARAgingRow: Identifiable {
    let id: Int64          // customer_id
    let customerName: String
    let current: Double    // not yet past due
    let days1_30: Double
    let days31_60: Double
    let days61_90: Double
    let over90: Double
    var total: Double { current + days1_30 + days31_60 + days61_90 + over90 }
    var displayCustomerName: String { userFacingEntityName(customerName) }
    var displayCustomerDetail: String? { userFacingEntityDetail(customerName) }
}

/// A/P aging: unpaid bills owed to a vendor, bucketed by how far past the due
/// date they are as of the report date. The payable mirror of `ARAgingRow`.
struct APAgingRow: Identifiable {
    let id: Int64          // vendor_id (0 if none)
    let vendorName: String
    let current: Double    // not yet past due (or no due date)
    let days1_30: Double
    let days31_60: Double
    let days61_90: Double
    let over90: Double
    var total: Double { current + days1_30 + days31_60 + days61_90 + over90 }
    var displayVendorName: String { userFacingEntityName(vendorName) }
    var displayVendorDetail: String? { userFacingEntityDetail(vendorName) }
}

enum Report1099Source {
    case historicalSnapshot
    case liveExpenseReview
}

struct Report1099Row: Identifiable {
    let id: Int64
    let vendorName: String
    let ein: String
    let totalPaid: Double
    let source: Report1099Source
    var displayVendorName: String { userFacingEntityName(vendorName) }
    var displayVendorDetail: String? { userFacingEntityDetail(vendorName) }
    var needs1099: Bool { totalPaid >= 600 }
}

struct VendorExpenseHistorySummary {
    let searchText: String
    let year: Int?
    let totalPaid: Double
    let transactionCount: Int
    let matchedVendorCount: Int
    let historical1099Total: Double?
}

struct CustomerStatementLine: Identifiable {
    let id: UUID
    let date: String
    let type: String        // "Estimate", "Invoice", "Payment", or "Customer Credit"
    let reference: String
    let amount: Double      // positive = charge, negative = credit
    let balance: Double

    init(date: String, type: String, reference: String, amount: Double, balance: Double) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.reference = reference
        self.amount = amount
        self.balance = balance
    }
}

struct BillRow: Identifiable {
    let id: Int64
    let vendorName: String
    let billDate: String
    let dueDate: String
    let amount: Double
    let accountName: String
    let jobID: Int64
    let jobName: String
    let memo: String
    let status: String
    let checkNumber: String
    var displayVendorName: String { userFacingEntityName(vendorName) }
    var displayVendorDetail: String? { userFacingEntityDetail(vendorName) }
    var displayJobName: String { userFacingEntityName(jobName) }
    var hasJob: Bool { jobID != 0 && !displayJobName.isEmpty }
    var displayMemo: String { userFacingMemo(memo) }
}

struct BillPaymentRow: Identifiable {
    let id: Int64
    let billID: Int64
    let paymentDate: String
    let amount: Double
    let paymentMethod: String
    let paymentAccountName: String
    let checkNumber: String
    let memo: String
    var displayMemo: String { userFacingMemo(memo) }
}

struct CompanyInfo {
    var name: String = "Your Company Name"
    var phone: String = ""
    var address1: String = ""
    var cityStateZip: String = ""
    var email: String = ""
    var licenseNumber: String = ""
    var paymentTerms: String = "Net 30"
    var invoiceFooter: String = "Thank you for your business."
}

struct CustomerActivitySnapshot {
    let openBalance: Double
    let estimateCount: Int
    let estimateTotal: Double
    let invoiceCount: Int
    let invoiceTotal: Double
    let paymentCount: Int
    let paymentTotal: Double
    let availableCreditCount: Int
    let availableCreditTotal: Double

    init(
        openBalance: Double,
        estimateCount: Int,
        estimateTotal: Double,
        invoiceCount: Int,
        invoiceTotal: Double,
        paymentCount: Int,
        paymentTotal: Double,
        availableCreditCount: Int = 0,
        availableCreditTotal: Double = 0
    ) {
        self.openBalance = openBalance
        self.estimateCount = estimateCount
        self.estimateTotal = estimateTotal
        self.invoiceCount = invoiceCount
        self.invoiceTotal = invoiceTotal
        self.paymentCount = paymentCount
        self.paymentTotal = paymentTotal
        self.availableCreditCount = availableCreditCount
        self.availableCreditTotal = availableCreditTotal
    }
}

struct JobProfitabilityRow: Identifiable, Hashable {
    let id: Int64
    let customerID: Int64
    let customerName: String
    let jobName: String
    let status: String
    let isActive: Bool
    let estimateCount: Int
    let estimateTotal: Double
    let invoiceCount: Int
    let invoicedTotal: Double
    let openInvoiceBalance: Double
    let expenseCount: Int
    let expenseTotal: Double

    var displayCustomerName: String { userFacingEntityName(customerName) }
    var estimateVsActualDelta: Double { estimateTotal - expenseTotal }
    var profit: Double { invoicedTotal - expenseTotal }
}

enum MemorizedTransactionType: String, CaseIterable, Identifiable, Codable {
    case estimate
    case invoice
    case check
    case salesReceipt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimate: return "Estimate Template"
        case .invoice: return "Invoice Template"
        case .check: return "Check Template"
        case .salesReceipt: return "Sales Receipt Template"
        }
    }
}

enum MemorizedReminderFrequency: String, CaseIterable, Identifiable, Codable {
    case none
    case once
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No reminder"
        case .once: return "One-time reminder"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    var intervalDays: Int? {
        switch self {
        case .none, .once: return nil
        case .weekly: return 7
        case .monthly: return 30
        case .quarterly: return 91
        case .yearly: return 365
        }
    }
}

struct MemorizedTransactionRow: Identifiable, Hashable {
    let id: Int64
    let name: String
    let type: MemorizedTransactionType
    let payloadJSON: String
    let isActive: Bool
    let updatedAt: String
    let reminderFrequency: MemorizedReminderFrequency
    let nextDueDate: String
    let lastUsedAt: String
    let notes: String

    var hasReminder: Bool {
        reminderFrequency != .none && !nextDueDate.isEmpty
    }

    var isDueSoon: Bool {
        guard hasReminder else { return false }
        let today = DateFormatter.isoDate.string(from: Date())
        guard let due = DateFormatter.isoDate.date(from: nextDueDate),
              let soon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else {
            return nextDueDate <= today
        }
        return due <= soon
    }

    var reminderStatusText: String {
        guard hasReminder else { return "Template only" }
        let today = DateFormatter.isoDate.string(from: Date())
        if nextDueDate < today {
            return "Overdue \(nextDueDate)"
        }
        if nextDueDate == today {
            return "Due today"
        }
        return "Due \(nextDueDate)"
    }
}

struct MemorizedLineTemplate: Codable, Hashable, Identifiable {
    var id = UUID()
    let description: String
    let quantity: Double
    let rate: Double
}

struct MemorizedEstimateTemplate: Codable, Hashable {
    let customerID: Int64
    let jobID: Int64
    let memo: String
    let status: String
    let lines: [MemorizedLineTemplate]
}

struct MemorizedInvoiceTemplate: Codable, Hashable {
    let customerID: Int64
    let jobID: Int64
    let memo: String
    let dueOffsetDays: Int
    let lines: [MemorizedLineTemplate]
}

struct MemorizedSalesReceiptTemplate: Codable, Hashable {
    let customerID: Int64
    let jobID: Int64
    let memo: String
    let paymentMethodID: Int64
    let depositAccountID: Int64
    let lines: [MemorizedLineTemplate]
}

struct MemorizedCheckTemplate: Codable, Hashable {
    let vendorID: Int64
    let payeeName: String
    let jobID: Int64
    let codingMode: CheckCodingMode
    let expenseAccountID: Int64
    let bankAccountID: Int64
    let memo: String
    let defaultAmount: Double
    let itemLines: [CheckItemDraft]
}

// MARK: - Bank Reconciliation (BNK-004)

/// Which register table a reconcilable item came from. `expense` is the
/// authoritative money-out register (checks, direct expenses, AND the mirror
/// rows recordBillPayments writes for bill payments), `deposit` is money in,
/// `transaction` is legacy imported GL history.
enum ReconcileSourceKind: String, Hashable, Codable {
    case expense
    case deposit
    case transaction

    /// The underlying SQLite table. Driven off the enum (never user input) so
    /// it is safe to interpolate into UPDATE statements.
    var tableName: String {
        switch self {
        case .expense: return "expenses"
        case .deposit: return "deposit_records"
        case .transaction: return "transactions"
        }
    }
}

/// One bank line eligible to be cleared during a reconciliation. `signedAmount`
/// is expressed against the bank balance: positive increases it (a deposit),
/// negative decreases it (a check/payment).
struct ReconcileItem: Identifiable, Hashable {
    let sourceKind: ReconcileSourceKind
    let sourceID: Int64
    let date: String
    let payee: String
    let reference: String
    let memo: String
    let signedAmount: Double
    var cleared: Bool
    let reconciliationID: Int64?

    var id: String { "\(sourceKind.rawValue):\(sourceID)" }
    var isDeposit: Bool { signedAmount >= 0 }
    var depositAmount: Double { signedAmount >= 0 ? signedAmount : 0 }
    var paymentAmount: Double { signedAmount < 0 ? -signedAmount : 0 }
    var displayPayee: String { userFacingEntityName(payee) }
    var displayMemo: String { userFacingMemo(memo) }
}

/// A bank account that actually carries register activity, offered as a
/// reconciliation target (e.g. Checking Account, Bank Of America).
struct ReconcileAccount: Identifiable, Hashable {
    let id: Int64
    let name: String
    let number: String
}

/// A reconciliation header row.
struct Reconciliation: Identifiable, Hashable {
    let id: Int64
    let accountID: Int64
    let accountName: String
    let statementDate: String
    let beginningBalance: Double
    let endingBalance: Double
    let clearedTotal: Double
    let status: String
    let createdAt: String
    let reconciledAt: String

    var isReconciled: Bool { status == "reconciled" }
}

/// Pure reconciliation math for the reconcile sheet — no database access, so it
/// can be exercised directly (and by the `prove_bank_reconciliation` harness).
struct ReconcileTally {
    let beginningBalance: Double
    let endingBalance: Double
    let clearedDeposits: Double
    let clearedPayments: Double

    init(beginningBalance: Double, endingBalance: Double, clearedItems: [ReconcileItem]) {
        self.beginningBalance = beginningBalance
        self.endingBalance = endingBalance
        self.clearedDeposits = clearedItems.reduce(0) { $0 + $1.depositAmount }
        self.clearedPayments = clearedItems.reduce(0) { $0 + $1.paymentAmount }
    }

    /// Net change the cleared items apply to the bank balance.
    var clearedChange: Double { clearedDeposits - clearedPayments }

    /// Bank balance implied by the cleared items.
    var clearedBalance: Double { beginningBalance + clearedChange }

    /// Statement balance minus what we've cleared. The reconcile target is 0.
    var difference: Double { endingBalance - clearedBalance }

    /// Allow a half-cent epsilon so floating-point rounding never blocks a
    /// genuinely balanced reconciliation.
    var isBalanced: Bool { abs(difference) < 0.005 }
}
