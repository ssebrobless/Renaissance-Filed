import SwiftUI

/// First-run setup wizard (issue #5). Shown once, when `OnboardingService.isFreshSetup` is
/// true, to turn an empty install into a ready set of books: name the company, pick a starter
/// chart of accounts, and (optionally) enter today's real opening balances. Migrants from
/// QuickBooks are pointed at Settings ▸ Import, which uses the same engine end-to-end.
struct OnboardingWizardView: View {
    @EnvironmentObject private var model: AppViewModel

    /// Called when the user finishes (or skips) setup — the window manager closes this window
    /// and opens the normal workspace.
    var onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, company, openingBalances, done
    }

    @State private var step: Step = .welcome
    @State private var companyName = ""
    @State private var template: ChartOfAccountsTemplate = .general
    @State private var assetAccounts: [AccountRow] = []
    @State private var openingBalanceText: [Int64: String] = [:]
    @State private var asOfDate = Date()
    @State private var accountsCreated = 0
    @State private var balancesEntered = 0
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AppTheme.ink3.opacity(0.3))
            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .company: companyStep
                    case .openingBalances: openingBalancesStep
                    case .done: doneStep
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(AppTheme.ink3.opacity(0.3))
            footer
        }
        .frame(width: 560, height: 560)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Welcome to Renaissance Filed", systemImage: "building.columns")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? AppTheme.accent : AppTheme.ink3.opacity(0.3))
                        .frame(height: 4)
                }
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.bad)
                    .font(.subheadline)
            }
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { goBack() }
                    .buttonStyle(.renaissanceSecondary)
            }
            primaryButton
        }
        .padding(20)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { step = .company }
                .buttonStyle(.renaissancePrimary)
        case .company:
            Button("Create My Books") { createBooks() }
                .buttonStyle(.renaissancePrimary)
                .disabled(companyName.trimmingCharacters(in: .whitespaces).isEmpty)
        case .openingBalances:
            Button("Continue") { applyOpeningBalances() }
                .buttonStyle(.renaissancePrimary)
        case .done:
            Button("Start Using Renaissance Filed") { onFinish() }
                .buttonStyle(.renaissancePrimary)
        }
    }

    private func goBack() {
        errorMessage = ""
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let's set up your books. This takes about a minute — you can change anything later in Settings.")
                .foregroundStyle(AppTheme.ink2)

            infoCard(icon: "sparkles", title: "Starting fresh",
                     body: "Name your company and pick a starter chart of accounts that fits your business. We'll create everything you need to start invoicing and tracking expenses.")

            infoCard(icon: "arrow.down.doc", title: "Moving from QuickBooks?",
                     body: "Finish this quick setup, then open Settings ▸ Import to bring in your lists (IIF) and transaction history (Journal CSV). A reconciliation check confirms your imported balances match QuickBooks to the penny.")
        }
    }

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Company name").font(.headline).foregroundStyle(AppTheme.ink)
                TextField("Your Company Name", text: $companyName)
                    .textFieldStyle(.roundedBorder)
                Text("Printed on your invoices, estimates, and statements.")
                    .font(.subheadline).foregroundStyle(AppTheme.ink3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What kind of business is this?").font(.headline).foregroundStyle(AppTheme.ink)
                Text("Sets up a starter chart of accounts. You can rename, add, or hide accounts anytime.")
                    .font(.subheadline).foregroundStyle(AppTheme.ink3)
                ForEach(ChartOfAccountsTemplate.allCases) { t in
                    templateCard(t)
                }
            }
        }
    }

    private var openingBalancesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Opening balances").font(.headline).foregroundStyle(AppTheme.ink)
                Text("Optional. Enter what each account is worth today so your books start from real figures instead of zero. Leave blank to start at zero — you can add these later.")
                    .font(.subheadline).foregroundStyle(AppTheme.ink3)
            }

            HStack {
                Text("As of").foregroundStyle(AppTheme.ink3)
                DatePicker("", selection: $asOfDate, displayedComponents: .date)
                    .labelsHidden()
            }

            if assetAccounts.isEmpty {
                Text("No asset accounts found.").foregroundStyle(AppTheme.ink3)
            } else {
                VStack(spacing: 8) {
                    ForEach(assetAccounts, id: \.id) { account in
                        HStack {
                            Text(account.name).foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("$").foregroundStyle(AppTheme.ink3)
                            TextField("0.00", text: bindingForBalance(account.id))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("You're all set", systemImage: "checkmark.seal.fill")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ok)

            summaryRow(icon: "building.2", text: "\(companyName) is ready to go.")
            summaryRow(icon: "list.bullet.rectangle", text: "\(accountsCreated) accounts created from the \(template.displayName) chart.")
            if balancesEntered > 0 {
                summaryRow(icon: "dollarsign.circle", text: "\(balancesEntered) opening balance\(balancesEntered == 1 ? "" : "s") recorded.")
            }

            Text("Next: create your first customer and invoice, or import from QuickBooks in Settings ▸ Import.")
                .foregroundStyle(AppTheme.ink2)
                .padding(.top, 4)
        }
    }

    // MARK: - Components

    private func infoCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                Text(body).font(.subheadline).foregroundStyle(AppTheme.ink2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.cardFillSoft))
    }

    private func templateCard(_ t: ChartOfAccountsTemplate) -> some View {
        Button {
            template = t
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template == t ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(template == t ? AppTheme.accent : AppTheme.ink3)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.displayName).font(.headline).foregroundStyle(AppTheme.ink)
                    Text(t.summary).font(.subheadline).foregroundStyle(AppTheme.ink2)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(template == t ? AppTheme.accent.opacity(0.14) : AppTheme.cardFillSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(template == t ? AppTheme.accent : .clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 22)
            Text(text).foregroundStyle(AppTheme.ink)
        }
    }

    private func bindingForBalance(_ id: Int64) -> Binding<String> {
        Binding(
            get: { openingBalanceText[id] ?? "" },
            set: { openingBalanceText[id] = $0 }
        )
    }

    // MARK: - Actions

    private func createBooks() {
        errorMessage = ""
        let name = companyName.trimmingCharacters(in: .whitespaces)
        do {
            let before = try model.db.fetchAccounts().count
            try OnboardingService.setupCompany(name: name, template: template, in: model.db)
            accountsCreated = try model.db.fetchAccounts().count - before
            assetAccounts = try model.db.fetchAccounts(type: "asset")
            step = .openingBalances
        } catch {
            errorMessage = "Couldn't create the books: \(error.localizedDescription)"
        }
    }

    private func applyOpeningBalances() {
        errorMessage = ""
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        let asOf = iso.string(from: asOfDate)
        var count = 0
        do {
            for account in assetAccounts {
                let raw = (openingBalanceText[account.id] ?? "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, let amount = Double(raw), abs(amount) > 0.005 else { continue }
                if try OnboardingService.recordOpeningBalance(
                    accountNamed: account.name, amount: amount, asOf: asOf, in: model.db) {
                    count += 1
                }
            }
            balancesEntered = count
            model.refreshCompanyInfo()
            model.refreshAccounts()
            step = .done
        } catch {
            errorMessage = "Couldn't save opening balances: \(error.localizedDescription)"
        }
    }
}
