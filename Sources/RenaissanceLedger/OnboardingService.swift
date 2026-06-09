import Foundation

/// A starter chart of accounts. Every template includes the canonical accounts the posting
/// layer relies on by name — Accounts Receivable, Accounts Payable, Undeposited Funds, a bank,
/// equity, and at least one income account — then layers on category accounts that fit the
/// kind of business. Pick one during onboarding; you can rename, add, or hide accounts later.
enum ChartOfAccountsTemplate: String, CaseIterable, Identifiable {
    case general
    case contractor
    case freelancer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General Small Business"
        case .contractor: return "Contractor / Trades"
        case .freelancer: return "Freelancer / Sole Proprietor"
        }
    }

    var summary: String {
        switch self {
        case .general: return "Sales & service income with everyday operating expenses."
        case .contractor: return "Job materials, subcontractor labor, equipment, and vehicle costs."
        case .freelancer: return "Service income with software, home-office, and equipment costs."
        }
    }

    /// Accounts the ledger needs in every chart (the names `rebuildJournal` looks up).
    private static let core: [(name: String, type: String, number: String)] = [
        ("Checking Account", "asset", "1000"),
        ("Savings Account", "asset", "1100"),
        ("Accounts Receivable", "asset", "1200"),
        ("Undeposited Funds", "asset", "1210"),
        ("Accounts Payable", "liability", "2000"),
        ("Credit Card", "liability", "2100"),
        ("Opening Balance Equity", "equity", "3900"),
        ("Owner's Equity", "equity", "3000"),
        ("Owner's Draw", "equity", "3100"),
    ]

    var accounts: [(name: String, type: String, number: String)] {
        switch self {
        case .general:
            return Self.core + [
                ("Sales", "income", "4000"),
                ("Service Income", "income", "4100"),
                ("Other Income", "income", "4900"),
                ("Cost of Goods Sold", "expense", "5000"),
                ("Advertising & Marketing", "expense", "6000"),
                ("Bank Service Charges", "expense", "6010"),
                ("Insurance", "expense", "6020"),
                ("Office Supplies", "expense", "6030"),
                ("Rent", "expense", "6040"),
                ("Utilities", "expense", "6050"),
                ("Meals & Entertainment", "expense", "6060"),
                ("Travel", "expense", "6070"),
                ("Professional Fees", "expense", "6080"),
                ("Miscellaneous Expense", "expense", "6900"),
            ]
        case .contractor:
            return Self.core + [
                ("Contract Income", "income", "4000"),
                ("Materials Reimbursement", "income", "4100"),
                ("Job Materials", "expense", "5000"),
                ("Subcontractor Labor", "expense", "5100"),
                ("Equipment & Tools", "expense", "5200"),
                ("Vehicle & Fuel", "expense", "5300"),
                ("Permits & Licenses", "expense", "5400"),
                ("Insurance", "expense", "5500"),
                ("Office & Admin", "expense", "5700"),
                ("Utilities", "expense", "5800"),
                ("Professional Fees", "expense", "5850"),
                ("Miscellaneous Expense", "expense", "5900"),
            ]
        case .freelancer:
            return Self.core + [
                ("Service Income", "income", "4000"),
                ("Software & Subscriptions", "expense", "6000"),
                ("Home Office", "expense", "6010"),
                ("Equipment", "expense", "6020"),
                ("Professional Fees", "expense", "6030"),
                ("Advertising & Marketing", "expense", "6040"),
                ("Meals & Entertainment", "expense", "6050"),
                ("Travel", "expense", "6060"),
                ("Bank Service Charges", "expense", "6070"),
                ("Miscellaneous Expense", "expense", "6900"),
            ]
        }
    }
}

/// First-run onboarding: detect a freshly installed (empty) company, set the company name,
/// lay down a starter chart of accounts, and optionally enter opening balances so the books
/// start from today's real figures rather than zero.
enum OnboardingService {

    /// The default company name in a brand-new database; treated as "not yet set up".
    static let placeholderCompanyName = "Your Company Name"

    /// True when the database looks freshly installed: no real company name and no business
    /// data has been entered. Drives whether to show the onboarding wizard on launch.
    static func isFreshSetup(_ db: SQLiteDatabase) throws -> Bool {
        let name = try db.fetchCompanyInfo().name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !name.isEmpty && name != placeholderCompanyName
        if hasName { return false }
        if try !db.fetchCustomers().isEmpty { return false }
        if try !db.fetchInvoices().isEmpty { return false }
        return true
    }

    /// Insert a starter chart of accounts. Accounts already present (matched case-insensitively
    /// by name) are skipped, so this is safe to run over the default seed or re-run. Returns the
    /// number of accounts actually added.
    @discardableResult
    static func applyChartTemplate(_ template: ChartOfAccountsTemplate, to db: SQLiteDatabase) throws -> Int {
        let existing = Set(try db.fetchAccounts().map { $0.name.lowercased() })
        var added = 0
        for a in template.accounts where !existing.contains(a.name.lowercased()) {
            _ = try db.insertGLAccount(name: a.name, type: a.type, number: a.number)
            added += 1
        }
        return added
    }

    /// Set up a company in one call: record the company name and lay down a starter chart.
    static func setupCompany(name: String,
                             template: ChartOfAccountsTemplate,
                             in db: SQLiteDatabase) throws {
        var info = try db.fetchCompanyInfo()
        info.name = name
        try db.saveCompanyInfo(info)
        try applyChartTemplate(template, to: db)
    }

    /// Record an opening balance for an account as of a date by posting it against Opening
    /// Balance Equity (a positive amount debits the account — correct for an asset like a bank
    /// balance; for a liability or equity account pass the natural credit-normal sign). Posted
    /// as a preserved `opening` ledger entry keyed by account, so re-entering replaces rather
    /// than stacks, and it survives a `rebuildJournal`. Returns false if the account is unknown.
    @discardableResult
    static func recordOpeningBalance(accountNamed name: String,
                                     amount: Double,
                                     asOf: String,
                                     in db: SQLiteDatabase) throws -> Bool {
        let accounts = try db.fetchAccounts()
        guard let account = accounts.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return false
        }
        if abs(amount) < 0.005 {
            // Zero means "no opening balance" — clear any prior one for this account.
            try db.deleteJournalEntries(kind: "opening", txnID: account.id)
            return true
        }
        let obe: Int64
        if let existing = accounts.first(where: { $0.name.lowercased() == "opening balance equity" }) {
            obe = existing.id
        } else {
            obe = try db.insertGLAccount(name: "Opening Balance Equity", type: "equity", number: "3900")
        }
        let lines: [SQLiteDatabase.JournalPosting] = amount > 0
            ? [SQLiteDatabase.JournalPosting(accountID: account.id, debit: amount, credit: 0),
               SQLiteDatabase.JournalPosting(accountID: obe, debit: 0, credit: amount)]
            : [SQLiteDatabase.JournalPosting(accountID: account.id, debit: 0, credit: -amount),
               SQLiteDatabase.JournalPosting(accountID: obe, debit: -amount, credit: 0)]
        try db.postJournalEntry(kind: "opening", txnID: account.id, date: asOf,
                                lines: lines, memo: "Opening balance")
        return true
    }
}
