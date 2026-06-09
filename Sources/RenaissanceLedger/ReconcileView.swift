import SwiftUI

/// Bank reconciliation sheet (BNK-004). Pick an account + statement ending date
/// and balance, tick off the lines that cleared, and commit when the difference
/// reaches zero. Mirrors the QuickBooks reconcile workflow Dad knows.
///
/// Sources are the authoritative register: `expenses` (checks/ACH out — and the
/// mirror rows bill payments write), `deposit_records` (money in), and legacy
/// imported `transactions`. `bill_payments` is intentionally not listed here to
/// avoid double-counting (see SQLiteDatabase reconcile DAO + the spec).
struct BankReconcileSheet: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    var onFinish: () -> Void

    @State private var accounts: [ReconcileAccount] = []
    @State private var selectedAccountID: Int64 = 0
    @State private var statementDate = Date()
    @State private var endingBalanceText = ""
    @State private var beginningBalance = 0.0
    @State private var items: [ReconcileItem] = []
    @State private var checkedIDs: Set<String> = []
    @State private var resumeReconciliationID: Int64?
    @State private var openingMode = false
    @State private var errorMessage = ""
    @State private var infoMessage = ""

    private var selectedAccountName: String {
        accounts.first { $0.id == selectedAccountID }?.name ?? ""
    }

    private var throughDate: String {
        DateFormatter.isoDate.string(from: statementDate)
    }

    private var endingBalanceValue: Double {
        Double(endingBalanceText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var checkedItems: [ReconcileItem] {
        items.filter { checkedIDs.contains($0.id) }
    }

    private var tally: ReconcileTally {
        ReconcileTally(beginningBalance: beginningBalance, endingBalance: endingBalanceValue, clearedItems: checkedItems)
    }

    private var canReconcile: Bool {
        selectedAccountID != 0 && !endingBalanceText.trimmingCharacters(in: .whitespaces).isEmpty && tally.isBalanced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if accounts.isEmpty {
                emptyState
            } else {
                columnHeader
                Divider()
                itemList
                Divider()
                footer
            }
        }
        .frame(width: 980, height: 720)
        .onAppear(perform: loadAccounts)
        .accessibilityIdentifier("reconcile.sheet")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reconcile Bank Account")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account").font(.caption).foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedAccountID) {
                        Text("- Select Account -").tag(Int64(0))
                        ForEach(accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .onChange(of: selectedAccountID) { _ in reloadForAccount() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Statement Ending Date").font(.caption).foregroundStyle(AppTheme.ink3)
                    SmartDateField(date: $statementDate)
                        .onChange(of: statementDate) { _ in reloadItems(preserveChecks: true) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Statement Ending Balance").font(.caption).foregroundStyle(AppTheme.ink3)
                    TextField("0.00", text: $endingBalanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beginning Balance").font(.caption).foregroundStyle(AppTheme.ink3)
                    Text(reconcileCurrency(beginningBalance))
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 140, alignment: .leading)
                        .help("Ending balance of the previous reconciliation for this account.")
                }
            }

            Toggle(isOn: $openingMode) {
                Text("Opening reconciliation (cutover) — clears every transaction on or before the statement date and sets this account's starting balance. Use once per account.")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)

            if resumeReconciliationID != nil && !openingMode {
                Text("Resuming an in-progress reconciliation. Your earlier check marks are restored.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
            if !infoMessage.isEmpty {
                Text(infoMessage).font(.caption).foregroundStyle(AppTheme.ok)
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(AppTheme.bad)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No reconcilable bank accounts found.")
                .font(.headline)
            Text("Accounts appear here once they carry checks, deposits, or imported transactions.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Items

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("✓").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 34)
            Text("Date").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
            Text("Payee / Source").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
            Text("Ref / Check").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .leading)
            Text("Payment").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .trailing)
            Text("Deposit").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
    }

    private var itemList: some View {
        Group {
            if items.isEmpty {
                Text("No uncleared transactions on or before this statement date.")
                    .foregroundStyle(AppTheme.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List(items) { item in
                    HStack(spacing: 0) {
                        Toggle("", isOn: binding(for: item))
                            .labelsHidden()
                            .frame(width: 34)
                        Text(item.date)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayPayee.isEmpty ? sourceLabel(item) : item.displayPayee)
                            if !item.displayMemo.isEmpty {
                                Text(item.displayMemo)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.reference.isEmpty ? "-" : item.reference)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.ink3)
                            .frame(width: 110, alignment: .leading)
                        Text(item.isDeposit ? "" : reconcileCurrency(item.paymentAmount))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.bad)
                            .frame(width: 120, alignment: .trailing)
                        Text(item.isDeposit ? reconcileCurrency(item.depositAmount) : "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.ok)
                            .frame(width: 120, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 28) {
                tallyColumn("Cleared Deposits", reconcileCurrency(tally.clearedDeposits))
                tallyColumn("Cleared Payments", reconcileCurrency(tally.clearedPayments))
                tallyColumn("Cleared Balance", reconcileCurrency(tally.clearedBalance))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Difference").font(.caption).foregroundStyle(AppTheme.ink3)
                    Text(reconcileCurrency(tally.difference))
                        .font(.title3.bold())
                        .foregroundStyle(tally.isBalanced ? AppTheme.ok : AppTheme.bad)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if openingMode {
                    Button("Create Opening Reconciliation") { openingCommit() }
                        .buttonStyle(.renaissancePrimary)
                        .disabled(selectedAccountID == 0 || endingBalanceText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Clears every transaction through the statement date and sets the starting balance.")
                } else {
                    Button("Save & Finish Later") { saveProgress() }
                        .buttonStyle(.renaissanceSecondary)
                        .disabled(selectedAccountID == 0)
                    Button("Reconcile Now") { commit() }
                        .buttonStyle(.renaissancePrimary)
                        .disabled(!canReconcile)
                        .help(canReconcile ? "" : "Difference must be 0.00 to reconcile.")
                }
            }
        }
        .padding()
    }

    private func tallyColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(AppTheme.ink3)
            Text(value).font(.system(size: 13, design: .monospaced))
        }
    }

    // MARK: - Bindings & helpers

    private func binding(for item: ReconcileItem) -> Binding<Bool> {
        Binding(
            get: { checkedIDs.contains(item.id) },
            set: { isOn in
                if isOn { checkedIDs.insert(item.id) } else { checkedIDs.remove(item.id) }
            }
        )
    }

    private func sourceLabel(_ item: ReconcileItem) -> String {
        switch item.sourceKind {
        case .expense: return "Check / Expense"
        case .deposit: return "Deposit"
        case .transaction: return "Imported transaction"
        }
    }

    // MARK: - Data

    private func loadAccounts() {
        do {
            accounts = try model.db.fetchReconcilableAccounts()
            if selectedAccountID == 0 { selectedAccountID = accounts.first?.id ?? 0 }
            reloadForAccount()
        } catch {
            errorMessage = "Could not load bank accounts: \(error.localizedDescription)"
        }
    }

    /// Switch accounts: resume an in-progress reconciliation if one exists,
    /// otherwise start fresh from the prior reconciled balance.
    private func reloadForAccount() {
        errorMessage = ""
        infoMessage = ""
        checkedIDs = []
        resumeReconciliationID = nil
        guard selectedAccountID != 0 else { items = []; beginningBalance = 0; return }
        do {
            if let inProgress = try model.db.fetchInProgressReconciliation(accountID: selectedAccountID) {
                resumeReconciliationID = inProgress.id
                beginningBalance = inProgress.beginningBalance
                endingBalanceText = inProgress.endingBalance == 0 ? "" : String(format: "%.2f", inProgress.endingBalance)
                if let date = DateFormatter.isoDate.date(from: inProgress.statementDate) {
                    statementDate = date
                }
            } else {
                beginningBalance = try model.db.reconciliationBeginningBalance(accountID: selectedAccountID)
            }
            reloadItems(preserveChecks: false)
            // Seed check marks from whatever the resumed reconciliation already cleared.
            checkedIDs = Set(items.filter { $0.cleared }.map { $0.id })
        } catch {
            errorMessage = "Could not load reconciliation: \(error.localizedDescription)"
        }
    }

    private func reloadItems(preserveChecks: Bool) {
        guard selectedAccountID != 0 else { items = []; return }
        do {
            items = try model.db.fetchReconcileItems(
                accountID: selectedAccountID,
                accountName: selectedAccountName,
                throughDate: throughDate,
                includeReconciliationID: resumeReconciliationID
            )
            if preserveChecks {
                // Drop checks for items that fell out of the (possibly narrower) date window.
                let available = Set(items.map { $0.id })
                checkedIDs = checkedIDs.intersection(available)
            }
        } catch {
            errorMessage = "Could not load transactions: \(error.localizedDescription)"
        }
    }

    private func saveProgress() {
        do {
            let saved = try model.db.saveReconciliationProgress(
                existingID: resumeReconciliationID,
                accountID: selectedAccountID,
                statementDate: throughDate,
                beginningBalance: beginningBalance,
                endingBalance: endingBalanceValue,
                clearedItems: checkedItems
            )
            resumeReconciliationID = saved.id
            onFinish()
            dismiss()
        } catch {
            errorMessage = "Could not save progress: \(error.localizedDescription)"
        }
    }

    private func commit() {
        do {
            _ = try model.db.commitReconciliation(
                existingID: resumeReconciliationID,
                accountID: selectedAccountID,
                statementDate: throughDate,
                beginningBalance: beginningBalance,
                endingBalance: endingBalanceValue,
                clearedItems: checkedItems
            )
            onFinish()
            dismiss()
        } catch {
            errorMessage = "Could not reconcile: \(error.localizedDescription)"
        }
    }

    private func openingCommit() {
        do {
            _ = try model.db.createOpeningReconciliation(
                accountID: selectedAccountID,
                accountName: selectedAccountName,
                throughDate: throughDate,
                statementEndingBalance: endingBalanceValue
            )
            onFinish()
            dismiss()
        } catch {
            errorMessage = "Could not create opening reconciliation: \(error.localizedDescription)"
        }
    }
}

private func reconcileCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
