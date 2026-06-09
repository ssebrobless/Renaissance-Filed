import Testing
import Foundation
@testable import RenaissanceLedger

/// First-run onboarding (issue #5): fresh-setup detection, starter charts of accounts,
/// one-call company setup, and opening balances that start the books from real figures.
@Suite("Onboarding")
struct OnboardingTests {

    @Test("A brand-new database is detected as needing setup")
    func freshDatabaseNeedsSetup() throws {
        let db = try TestDB.make()
        #expect(try OnboardingService.isFreshSetup(db))
    }

    @Test("Once a company name is set, onboarding is no longer offered")
    func setupClearsFreshFlag() throws {
        let db = try TestDB.make()
        try OnboardingService.setupCompany(name: "Bristow Tile Co", template: .contractor, in: db)
        #expect(try !OnboardingService.isFreshSetup(db))
        #expect(try db.fetchCompanyInfo().name == "Bristow Tile Co")
    }

    @Test("Entering business data also counts as set up, even without a company name")
    func businessDataCountsAsSetup() throws {
        let db = try TestDB.make()
        _ = try db.insertCustomer(name: "Acme Co", company: "", primaryContact: "",
                                  email: "", phone: "", address: "", city: "", state: "", zip: "")
        #expect(try !OnboardingService.isFreshSetup(db))
    }

    @Test("Every template includes the accounts the ledger relies on by name")
    func templatesIncludeCanonicalAccounts() throws {
        for template in ChartOfAccountsTemplate.allCases {
            let names = Set(template.accounts.map { $0.name })
            #expect(names.contains("Accounts Receivable"))
            #expect(names.contains("Accounts Payable"))
            #expect(names.contains("Undeposited Funds"))
            #expect(names.contains("Opening Balance Equity"))
            #expect(template.accounts.contains { $0.type == "income" })
            #expect(template.accounts.contains { $0.type == "asset" })
        }
    }

    @Test("Applying a template lays down its chart and is safe to re-run")
    func applyTemplateIsIdempotent() throws {
        let db = try TestDB.make()
        let added = try OnboardingService.applyChartTemplate(.freelancer, to: db)
        #expect(added > 0)
        let names = Set(try db.fetchAccounts().map { $0.name })
        #expect(names.contains("Software & Subscriptions"))
        #expect(names.contains("Home Office"))

        let addedAgain = try OnboardingService.applyChartTemplate(.freelancer, to: db)
        #expect(addedAgain == 0)   // everything already present
    }

    @Test("An opening bank balance posts a balanced entry that shows on the books")
    func openingBalancePostsBalanced() throws {
        let db = try TestDB.make()
        try OnboardingService.setupCompany(name: "Jane Designs", template: .freelancer, in: db)

        let ok = try OnboardingService.recordOpeningBalance(
            accountNamed: "Checking Account", amount: 5_000, asOf: "2026-01-01", in: db)
        #expect(ok)

        #expect(try db.ledgerBalance(named: "Checking Account") == 5_000)
        #expect(try db.ledgerBalance(named: "Opening Balance Equity") == -5_000)

        let totals = try db.trialBalanceTotals()
        #expect(abs(totals.debits - totals.credits) < 0.005)
    }

    @Test("Opening balances survive a rebuildJournal and re-entry replaces rather than stacks")
    func openingBalanceSurvivesAndReplaces() throws {
        let db = try TestDB.make()
        try OnboardingService.setupCompany(name: "Jane Designs", template: .freelancer, in: db)
        _ = try OnboardingService.recordOpeningBalance(
            accountNamed: "Checking Account", amount: 5_000, asOf: "2026-01-01", in: db)

        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Checking Account") == 5_000)   // preserved

        _ = try OnboardingService.recordOpeningBalance(
            accountNamed: "Checking Account", amount: 8_000, asOf: "2026-01-01", in: db)
        #expect(try db.ledgerBalance(named: "Checking Account") == 8_000)   // replaced, not 13,000
    }

    @Test("An unknown account name is reported rather than silently dropped")
    func unknownAccountReturnsFalse() throws {
        let db = try TestDB.make()
        try OnboardingService.setupCompany(name: "Jane Designs", template: .freelancer, in: db)
        let ok = try OnboardingService.recordOpeningBalance(
            accountNamed: "Nonexistent Account", amount: 100, asOf: "2026-01-01", in: db)
        #expect(!ok)
    }
}
