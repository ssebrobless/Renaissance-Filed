import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Migrate from QuickBooks: a file-picker front end for the import engines.
/// Step 1 brings in lists (chart of accounts, customers, vendors) from a QuickBooks IIF
/// export; step 2 brings in transaction history from a Journal-report CSV; step 3 is the
/// reconciliation check that confirms an imported balance matches your last QuickBooks
/// statement. The heavy lifting lives in QuickBooksIIFImportService / QuickBooksJournalImportService.
struct QuickBooksImportSection: View {
    @EnvironmentObject private var model: AppViewModel

    @State private var listsResult = ""
    @State private var listsIsError = false
    @State private var journalResult = ""
    @State private var journalIsError = false

    @State private var reconcileAccount = ""
    @State private var reconcileExpected = ""
    @State private var reconcileResult = ""
    @State private var reconcileMatches = false
    @State private var reconcileRan = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Migrate from QuickBooks", systemImage: "arrow.down.doc")
                    .font(.headline)
                Text("Bring your books over from QuickBooks Desktop. Import your lists, then your transaction history, then confirm the imported balances match your last QuickBooks statement. Imported history is preserved and coexists with anything you enter going forward.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink3)

                stepOneLists
                Divider()
                stepTwoTransactions
                Divider()
                stepThreeReconcile
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Step 1: Lists (IIF)

    private var stepOneLists: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Import lists (IIF)").font(.subheadline.weight(.semibold))
            Text("In QuickBooks: File ▸ Utilities ▸ Export ▸ Lists to IIF Files. Imports the chart of accounts, customers, and vendors. Names already present are skipped, so it's safe to re-run.")
                .font(.caption).foregroundStyle(AppTheme.ink3)
            HStack {
                Button("Choose IIF File…") { importLists() }
                    .buttonStyle(.renaissancePrimary)
                if !listsResult.isEmpty {
                    Label(listsResult, systemImage: listsIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(listsIsError ? AppTheme.bad : AppTheme.ok)
                }
            }
        }
    }

    // MARK: - Step 2: Transactions (Journal CSV)

    private var stepTwoTransactions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("2. Import transactions (Journal CSV)").font(.subheadline.weight(.semibold))
            Text("In QuickBooks: Reports ▸ Accountant & Taxes ▸ Journal, set the date range, then export to CSV. Import lists first so accounts match by name. Re-importing replaces the prior import rather than duplicating it.")
                .font(.caption).foregroundStyle(AppTheme.ink3)
            HStack {
                Button("Choose Journal CSV…") { importTransactions() }
                    .buttonStyle(.renaissancePrimary)
                if !journalResult.isEmpty {
                    Label(journalResult, systemImage: journalIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(journalIsError ? AppTheme.bad : AppTheme.ok)
                }
            }
        }
    }

    // MARK: - Step 3: Reconciliation check

    private var stepThreeReconcile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3. Confirm a balance matches QuickBooks").font(.subheadline.weight(.semibold))
            Text("Enter an account name and the balance QuickBooks shows for it (for example, your checking account on your last statement). This confirms the import landed to the penny.")
                .font(.caption).foregroundStyle(AppTheme.ink3)
            HStack(spacing: 8) {
                TextField("Account name", text: $reconcileAccount)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                TextField("QuickBooks balance", text: $reconcileExpected)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button("Check") { runReconcile() }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(reconcileAccount.trimmingCharacters(in: .whitespaces).isEmpty
                              || Double(reconcileExpected.trimmingCharacters(in: .whitespaces)) == nil)
            }
            if reconcileRan {
                Label(reconcileResult, systemImage: reconcileMatches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(reconcileMatches ? AppTheme.ok : AppTheme.bad)
            }
        }
    }

    // MARK: - Actions

    private func importLists() {
        guard let url = chooseFile(
            message: "Select a QuickBooks IIF export of your lists.",
            extensions: ["iif"]) else { return }
        guard let text = readText(url) else {
            listsIsError = true; listsResult = "Couldn't read that file."; return
        }
        do {
            let s = try QuickBooksIIFImportService.importIIF(text, into: model.db)
            model.refreshAccounts(); model.refreshCustomers(); model.refreshVendors()
            listsIsError = false
            listsResult = "Imported \(s.accounts) accounts, \(s.customers) customers, \(s.vendors) vendors"
                + (s.skipped > 0 ? " (\(s.skipped) already present)" : "") + "."
        } catch {
            listsIsError = true
            listsResult = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importTransactions() {
        guard let url = chooseFile(
            message: "Select a QuickBooks Journal report exported to CSV.",
            extensions: ["csv"]) else { return }
        guard let text = readText(url) else {
            journalIsError = true; journalResult = "Couldn't read that file."; return
        }
        do {
            let s = try QuickBooksJournalImportService.importJournalCSV(text, into: model.db)
            model.refreshAccounts()
            journalIsError = false
            journalResult = "Imported \(s.transactions) transactions (\(s.lines) lines)"
                + (s.accountsCreated > 0 ? ", created \(s.accountsCreated) new accounts" : "")
                + (s.balancingPlug > 0.005 ? String(format: ", $%.2f routed to Opening Balance Equity", s.balancingPlug) : "")
                + "."
        } catch {
            journalIsError = true
            journalResult = "Import failed: \(error.localizedDescription)"
        }
    }

    private func runReconcile() {
        let name = reconcileAccount.trimmingCharacters(in: .whitespaces)
        guard let expected = Double(reconcileExpected.trimmingCharacters(in: .whitespaces)) else { return }
        reconcileRan = true
        do {
            let check = try QuickBooksJournalImportService.reconcile(accountNamed: name, expected: expected, in: model.db)
            reconcileMatches = check.matches
            if check.matches {
                reconcileResult = "\(name) matches QuickBooks at \(currency(check.actual))."
            } else {
                reconcileResult = "\(name) is \(currency(check.actual)) here vs \(currency(expected)) in QuickBooks "
                    + "(off by \(currency(check.difference)))."
            }
        } catch {
            reconcileMatches = false
            reconcileResult = "Couldn't check that account: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func chooseFile(message: String, extensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = message
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) } + [.plainText, .commaSeparatedText, .text, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private func readText(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }
        return try? String(contentsOf: url, encoding: .isoLatin1)   // QuickBooks IIF is often Latin-1
    }

    private func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}
