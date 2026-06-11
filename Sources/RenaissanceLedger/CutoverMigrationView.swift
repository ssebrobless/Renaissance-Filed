import SwiftUI

/// Settings ▸ Migration cutover (ADR-002). After importing a book from QuickBooks, the imperfect
/// history can't be rebuilt into statements that tie out, so instead you draw a cutover line:
/// enter each balance-sheet account's balance as of a date, and from there forward the computed
/// statements are correct. Pre-cutover activity is captured by the opening entry, not posted.
/// Drives `MigrationBackfillService`; writes only the derived ledger + one config row, and is
/// reversible.
struct CutoverMigrationSection: View {
    @EnvironmentObject private var model: AppViewModel

    @State private var cutoverDate = Date()
    @State private var balanceText: [Int64: String] = [:]
    @State private var accounts: [AccountRow] = []
    @State private var activeCutover: String?
    @State private var message = ""
    @State private var isError = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Migration Cutover (opening balances)", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Text("For books brought over from QuickBooks. Set a cutover date and enter each account's balance as of that date (from your last Balance Sheet or reconciled statement). The computed Profit & Loss and Balance Sheet are then correct from the cutover forward, and pre-cutover history is captured as an opening balance instead of being re-posted. This writes only the derived ledger and is reversible.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink3)

                if let activeCutover {
                    activeBanner(activeCutover)
                }

                HStack(spacing: 8) {
                    Text("Cutover date").foregroundStyle(AppTheme.ink3)
                    DatePicker("", selection: $cutoverDate, displayedComponents: .date)
                        .labelsHidden()
                }

                balanceEntry

                HStack(spacing: 10) {
                    Button("Apply Cutover") { apply() }
                        .buttonStyle(.renaissancePrimary)
                    if !message.isEmpty {
                        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(isError ? AppTheme.bad : AppTheme.ok)
                    }
                }
                .padding(.top, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
    }

    // MARK: - Subviews

    private func activeBanner(_ date: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.ok)
            Text("A cutover is active as of \(date). Pre-cutover activity is captured by opening balances.")
                .font(.subheadline).foregroundStyle(AppTheme.ink2)
            Spacer()
            Button("Remove Cutover") { revert() }
                .buttonStyle(.renaissanceSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.cardFillSoft))
    }

    private var balanceEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account balances as of the cutover")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            Text("Enter balances as they appear on your Balance Sheet (assets positive; a liability or equity balance positive). Leave an account blank for zero. Equity is balanced automatically through Opening Balance Equity.")
                .font(.caption).foregroundStyle(AppTheme.ink3)
            ForEach(accounts) { account in
                HStack {
                    Text(account.name).foregroundStyle(AppTheme.ink)
                    Text(account.type).font(.caption).foregroundStyle(AppTheme.ink3)
                    Spacer()
                    Text("$").foregroundStyle(AppTheme.ink3)
                    TextField("0.00", text: binding(account.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .multilineTextAlignment(.trailing)
                }
            }
            if accounts.isEmpty {
                Text("No balance-sheet accounts found.").font(.subheadline).foregroundStyle(AppTheme.ink3)
            }
        }
    }

    // MARK: - Logic

    /// Convert an entered Balance-Sheet figure to a signed ledger balance (debit − credit):
    /// debit-normal accounts (assets) keep the sign, credit-normal accounts (liabilities,
    /// equity) flip it.
    private func signedBalance(for account: AccountRow, entered: Double) -> Double {
        let creditNormal = (account.type == "liability" || account.type == "equity" || account.type == "income")
        return creditNormal ? -entered : entered
    }

    private func binding(_ id: Int64) -> Binding<String> {
        Binding(get: { balanceText[id] ?? "" }, set: { balanceText[id] = $0 })
    }

    private func load() {
        // Balance-sheet accounts only; Opening Balance Equity is the automatic plug, so it's not entered.
        let types: Set<String> = ["asset", "liability", "equity"]
        accounts = ((try? model.db.fetchAccounts()) ?? [])
            .filter { types.contains($0.type) && $0.name.lowercased() != "opening balance equity" }
            .sorted { ($0.type, $0.number, $0.name) < ($1.type, $1.number, $1.name) }
        activeCutover = try? model.db.ledgerCutoverDate()
    }

    private func apply() {
        message = ""
        let iso = DateFormatter.isoDate
        let date = iso.string(from: cutoverDate)
        var openings: [MigrationBackfillService.OpeningBalance] = []
        for account in accounts {
            let raw = (balanceText[account.id] ?? "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let entered = Double(raw), abs(entered) > 0.005 else { continue }
            openings.append(.init(account.name, signedBalance(for: account, entered: entered)))
        }
        do {
            let result = try MigrationBackfillService.applyCutover(date: date, openingBalances: openings, in: model.db)
            _ = try model.db.rebuildJournal()
            model.refreshAccounts()
            activeCutover = try? model.db.ledgerCutoverDate()
            isError = false
            message = "Cutover set as of \(date); \(result.applied) opening balance\(result.applied == 1 ? "" : "s") recorded"
                + (result.notFound.isEmpty ? "." : " (\(result.notFound.count) account(s) not found).")
        } catch {
            isError = true
            message = "Couldn't apply the cutover: \(error.localizedDescription)"
        }
    }

    private func revert() {
        message = ""
        do {
            try MigrationBackfillService.revertCutover(in: model.db)
            _ = try model.db.rebuildJournal()
            model.refreshAccounts()
            activeCutover = nil
            isError = false
            message = "Cutover removed; the ledger posts all history directly again."
        } catch {
            isError = true
            message = "Couldn't remove the cutover: \(error.localizedDescription)"
        }
    }
}
