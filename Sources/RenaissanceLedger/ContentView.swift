import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            navigatorSidebar
                .frame(width: 268)
                .background(AppTheme.canvas.ignoresSafeArea())

            Divider()

            navigatorDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface.ignoresSafeArea())
        }
        .accessibilityIdentifier("ledger.navigator")
        .overlay(alignment: .bottomLeading) {
            Text(model.statusMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)
                .padding(8)
                .background(AppTheme.panel.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)
                .accessibilityIdentifier("ledger.statusMessage")
        }
        .task {
            model.applyHarnessPresentationIfNeeded()
        }
        .onChange(of: model.selectedTab) { tab in
            if tab != .settings {
                AppAppearanceSettings.closeSharedColorPanel()
            }
        }
    }

    // MARK: Sidebar

    private var navigatorSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Renaissance Filed")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.accent)
                Text("Navigator")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    Button {
                        WorkspaceWindowManager.shared.showNavigatorLauncher()
                    } label: {
                        homeButtonLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("navigator.button.home")

                    ForEach(NavigatorRoute.primary, id: \.self) { route in
                        navButton(for: route)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            Divider()
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("Main Windows")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink3)
                    .padding(.top, 12)

                Button {
                    WorkspaceWindowManager.shared.showCenterWindow()
                } label: {
                    Label("Customer Center / Register", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.renaissanceSecondary)
                .accessibilityIdentifier("navigator.shortcut.center")

                Button {
                    WorkspaceWindowManager.shared.showReportCenterWindow()
                } label: {
                    Label("Report Center", systemImage: "chart.bar.doc.horizontal")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.renaissanceSecondary)
                .accessibilityIdentifier("navigator.shortcut.reportCenter")

                Button {
                    WorkspaceWindowManager.shared.showHelpWindow()
                } label: {
                    Label("Help Me", systemImage: "questionmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.renaissancePrimary)
                .accessibilityIdentifier("navigator.shortcut.helpMe")

                Button {
                    WorkspaceWindowManager.shared.showTechSupportWindow()
                } label: {
                    Label("Tech Support", systemImage: "wrench.and.screwdriver.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.renaissancePrimary)
                .accessibilityIdentifier("navigator.shortcut.techSupport")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
    }

    private var homeButtonLabel: some View {
        let isSelected = model.selectedTab == .workspace
        return HStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Home")
                    .font(.headline)
                    .foregroundStyle(AppTheme.bodyText)
                Text("Status & quick stats")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AppTheme.panel : AppTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppTheme.accent.opacity(0.55) : AppTheme.hairline, lineWidth: 1)
        )
    }

    private func navButton(for route: NavigatorRoute) -> some View {
        let isSelected = model.selectedTab == route.tab
        return Button {
            model.selectedTab = route.tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: route.symbol)
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.label)
                        .font(.headline)
                        .foregroundStyle(AppTheme.bodyText)
                    Text(route.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.panel : AppTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.55) : AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("navigator.button.\(route.tab.rawValue)")
    }

    // MARK: Detail

    @ViewBuilder
    private var navigatorDetail: some View {
        switch model.selectedTab {
        case .workspace: navigatorHome
        case .mail: MailReviewView()
        case .customers: CustomersView()
        case .vendors: VendorsView()
        case .lists: ListsView()
        case .estimates: EstimatesView()
        case .invoices: InvoiceTabView()
        case .salesReceipts: SalesReceiptsView()
        case .expenses: ExpensesView()
        case .bills: BillsView()
        case .reports: ReportsView()
        case .sync: SyncCenterView()
        case .importCenter: ImportCenterView()
        case .history: TransactionsView()
        case .documents: DocumentsView()
        case .settings: SettingsView()
        }
    }

    private var navigatorHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome")
                        .font(.largeTitle.bold())
                    Text("Use the Navigator on the left to jump to any section. The three floating windows — Customer Center, Register, and Report Center — handle the daily flows.")
                        .font(.body)
                        .foregroundStyle(AppTheme.ink3)
                        .frame(maxWidth: 720, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                    quickStat("Customers", value: "\(model.customers.count)", symbol: "person.2")
                    quickStat(
                        "Open invoices",
                        value: "\(model.nativeInvoices.filter { $0.balance > 0 && $0.status != "void" }.count)",
                        symbol: "doc.text"
                    )
                    quickStat(
                        "Open estimates",
                        value: "\(model.estimates.filter { $0.status == "draft" || $0.status == "sent" }.count)",
                        symbol: "doc.plaintext"
                    )
                    quickStat("Vendors / Payees", value: "\(model.vendors.count)", symbol: "building.2")
                    quickStat("Service items", value: "\(model.serviceItems.count)", symbol: "list.bullet.rectangle")
                    quickStat("Documents", value: "\(model.documents.count)", symbol: "folder")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips")
                        .font(.headline)
                    Text("• Click any section on the left to open it here.")
                    Text("• If you accidentally close Customer Center or Report Center, use the buttons at the bottom of the Navigator to bring them back.")
                    Text("• The Navigator stays open as long as the app is running so you always have a way to reach every section.")
                }
                .font(.callout)
                .foregroundStyle(AppTheme.ink3)
                .frame(maxWidth: 720, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func quickStat(_ label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(AppTheme.ink3)
                Text(value).font(.title2.bold())
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardFill)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum NavigatorRoute: Hashable {
    case mail
    case estimates
    case invoices
    case salesReceipts
    case expenses
    case bills
    case vendors
    case lists
    case documents
    case sync
    case importCenter
    case settings

    static let primary: [NavigatorRoute] = [
        .mail,
        .estimates,
        .invoices,
        .salesReceipts,
        .expenses,
        .bills,
        .vendors,
        .lists,
        .documents,
        .sync,
        .importCenter,
        .settings,
    ]

    var tab: AppTab {
        switch self {
        case .mail: return .mail
        case .estimates: return .estimates
        case .invoices: return .invoices
        case .salesReceipts: return .salesReceipts
        case .expenses: return .expenses
        case .bills: return .bills
        case .vendors: return .vendors
        case .lists: return .lists
        case .documents: return .documents
        case .sync: return .sync
        case .importCenter: return .importCenter
        case .settings: return .settings
        }
    }

    var label: String {
        switch self {
        case .mail: return "Mail"
        case .estimates: return "Estimates"
        case .invoices: return "Invoices"
        case .salesReceipts: return "Receipts"
        case .expenses: return "Expenses / Checks"
        case .bills: return "Bills"
        case .vendors: return "Payees"
        case .lists: return "Lists"
        case .documents: return "Documents"
        case .sync: return "Sync"
        case .importCenter: return "Import"
        case .settings: return "Settings"
        }
    }

    var compactLabel: String {
        switch self {
        case .salesReceipts: return "Receipts"
        case .expenses: return "Expenses"
        case .importCenter: return "Import"
        default: return label
        }
    }

    var subtitle: String {
        switch self {
        case .mail: return "Inbox & order sheets"
        case .estimates: return "Drafts to converted"
        case .invoices: return "Issue & receive payment"
        case .salesReceipts: return "Cash sales"
        case .expenses: return "Checks & ACH"
        case .bills: return "Bills payable"
        case .vendors: return "Vendor & 1099 list"
        case .lists: return "Items, terms, methods"
        case .documents: return "Archived files"
        case .sync: return "Backup & restore"
        case .importCenter: return "Folder import"
        case .settings: return "App preferences"
        }
    }

    var symbol: String {
        switch self {
        case .mail: return "envelope.badge"
        case .estimates: return "doc.plaintext"
        case .invoices: return "doc.text"
        case .salesReceipts: return "doc.text.fill"
        case .expenses: return "creditcard"
        case .bills: return "tray.full"
        case .vendors: return "building.2"
        case .lists: return "list.bullet.rectangle"
        case .documents: return "folder"
        case .sync: return "arrow.triangle.branch"
        case .importCenter: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}

private struct ImportCenterView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Renaissance Filed Import Center")
                    .font(.title2.bold())
                Spacer()
                Button("Import Transfer Folder") {
                    model.importFromFolderPicker()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(model.isImporting)

                Button("Refresh") {
                    model.refreshAll()
                }
                .disabled(model.isImporting)
            }

            summaryCards

            Text("Recent Import Sessions")
                .font(.headline)

            List(model.importSessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Session #\(session.id)").font(.subheadline.bold())
                        Spacer()
                        Text(session.status).foregroundStyle(statusColor(session.status))
                    }
                    Text(session.startedAt).font(.footnote)
                    Text(session.transferRoot).font(.footnote).foregroundStyle(AppTheme.ink3)
                    if !session.summary.isEmpty {
                        Text(session.summary).font(.footnote)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            statCard(title: "Transactions", value: "\(model.transactions.count)")
            statCard(title: "Invoices", value: "\(model.invoices.count)")
            statCard(title: "Payouts", value: "\(model.payouts.count)")
            statCard(title: "Documents", value: "\(model.documents.count)")
            statCard(title: "Issues", value: "\(model.issues.count)")
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(AppTheme.ink3)
            Text(value).font(.title3.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline, lineWidth: 1))
        .cornerRadius(8)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed": return .green
        case "completed_with_issues": return .orange
        case "failed": return .red
        default: return .secondary
        }
    }
}

private struct TransactionsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var mode = "register"
    @State private var selectedBankAccountID: Int64 = 0
    @State private var showRecordDepositSheet = false
    @State private var showReconcileSheet = false
    @State private var undepositedPayments: [PaymentReceivedRow] = []
    @State private var recentDeposits: [DepositRecordRow] = []
    @State private var selectedDeposit: DepositRecordRow?
    @State private var selectedDepositPayments: [PaymentReceivedRow] = []

    private var bankAccounts: [AccountRow] {
        model.accounts.filter { $0.type == "asset" }
    }

    private var undepositedTotal: Double {
        undepositedPayments.reduce(0) { $0 + $1.amount }
    }

    private var registerRows: [ExpenseRow] {
        let base = model.expenses.filter { expense in
            selectedBankAccountID == 0 || expense.paymentAccountID == selectedBankAccountID
        }
        return base.sorted { lhs, rhs in
            if lhs.expenseDate != rhs.expenseDate { return lhs.expenseDate > rhs.expenseDate }
            if lhs.checkNumber != rhs.checkNumber { return lhs.checkNumber > rhs.checkNumber }
            return lhs.id > rhs.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Register")
                        .font(.title2.bold())
                    Text("A QuickBooks-style view of checks and imported transaction history.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                Button("Reconcile…") {
                    showReconcileSheet = true
                }
                .buttonStyle(.renaissanceSecondary)
                Picker("", selection: $mode) {
                    Text("Check Register").tag("register")
                    Text("Imported History").tag("imported")
                    Text("Deposits").tag("deposits")
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }
            .padding(20)

            Divider()

            if mode == "register" {
                checkRegisterView
            } else if mode == "imported" {
                importedHistoryView
            } else {
                depositsView
            }
        }
        .onAppear { refreshDepositContext() }
        .onChange(of: mode) { newMode in
            if newMode == "deposits" {
                refreshDepositContext()
            }
        }
        .sheet(isPresented: $showRecordDepositSheet) {
            RecordDepositSheet {
                showRecordDepositSheet = false
                refreshDepositContext()
                model.refreshNativeInvoices()
                model.refreshSalesReceipts()
            }
            .environmentObject(model)
        }
        .sheet(item: $selectedDeposit) { deposit in
            DepositDetailSheet(deposit: deposit, payments: selectedDepositPayments)
        }
        .sheet(isPresented: $showReconcileSheet) {
            BankReconcileSheet {
                showReconcileSheet = false
                model.refreshExpenses()
                refreshDepositContext()
            }
            .environmentObject(model)
        }
    }

    private var checkRegisterView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Bank Account", selection: $selectedBankAccountID) {
                    Text("All Bank Accounts").tag(Int64(0))
                    ForEach(bankAccounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                .frame(width: 260)

                Spacer()

                Text("\(registerRows.count) check row" + (registerRows.count == 1 ? "" : "s"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                Text("✓").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 28, alignment: .center)
                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Check #").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 90, alignment: .leading)
                Text("Payee").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Category").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 190, alignment: .leading)
                Text("Memo").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Amount").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if registerRows.isEmpty {
                emptyRegisterState("No check activity is available for this bank account.")
            } else {
                List(registerRows) { expense in
                    HStack(spacing: 0) {
                        Image(systemName: expense.cleared ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(expense.cleared ? AppTheme.ok : AppTheme.ink3.opacity(0.4))
                            .font(.system(size: 12))
                            .frame(width: 28, alignment: .center)
                            .help(expense.cleared ? "Reconciled / cleared" : "Not yet reconciled")
                        Text(expense.expenseDate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(expense.checkNumber.isEmpty ? "-" : expense.checkNumber)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.displayVendorName)
                            if let detail = expense.displayVendorDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(expense.accountName)
                            .frame(width: 190, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(expense.displayMemo.isEmpty ? "-" : expense.displayMemo)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(formatCurrency(expense.amount))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120, alignment: .trailing)
                            .foregroundStyle(AppTheme.bad)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private var importedHistoryView: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search imported transactions", text: $model.transactionSearch)
                    .textFieldStyle(.roundedBorder)
                Button("Apply") { model.refreshTransactions() }
                Button("Reset") {
                    model.transactionSearch = ""
                    model.refreshTransactions()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            List(model.transactions) { row in
                HStack(spacing: 12) {
                    Text(row.date).frame(width: 100, alignment: .leading)
                    Text(row.payee).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.account).frame(width: 180, alignment: .leading)
                    Text(row.memo).frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatCurrency(row.amount)).frame(width: 120, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .regular, design: .monospaced))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var depositsView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Undeposited Funds")
                        .font(.headline)
                    Text("Group customer payments into the bank deposit Dad actually makes.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatCurrency(undepositedTotal))
                        .font(.title3.bold())
                    Text("\(undepositedPayments.count) payment" + (undepositedPayments.count == 1 ? "" : "s") + " waiting")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }

                Button("Refresh") {
                    refreshDepositContext()
                }
                .buttonStyle(.renaissanceSecondary)

                Button("Record Deposit") {
                    refreshDepositContext()
                    showRecordDepositSheet = true
                }
                .buttonStyle(.renaissancePrimary)
                .disabled(undepositedPayments.isEmpty)
            }
            .padding()

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Payments Waiting To Deposit")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ink3)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    if undepositedPayments.isEmpty {
                        depositEmptyState(
                            icon: "tray",
                            title: "No Undeposited Payments",
                            message: "Receive Payment can send customer money here first. Once payments appear, group them into a bank deposit."
                        )
                    } else {
                        List(undepositedPayments) { payment in
                            HStack(spacing: 0) {
                                Text(payment.paymentDate)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 96, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(payment.customerDisplayName)
                                    if let detail = payment.customerDisplayDetail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(payment.invoiceNumber.isEmpty ? "-" : payment.invoiceNumber)
                                    .frame(width: 130, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(payment.method.isEmpty ? "-" : payment.method)
                                    .frame(width: 110, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(formatCurrency(payment.amount))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                .frame(minWidth: 560)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent Deposits")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ink3)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    if recentDeposits.isEmpty {
                        depositEmptyState(
                            icon: "banknote",
                            title: "No Deposits Recorded",
                            message: "Recorded deposits will show here after customer payments are grouped."
                        )
                    } else {
                        List(recentDeposits) { deposit in
                            Button {
                                openDepositDetail(deposit)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(deposit.depositDate)
                                            .font(.system(size: 12, design: .monospaced))
                                        Spacer()
                                        Text(formatCurrency(deposit.totalAmount))
                                            .font(.system(size: 12, design: .monospaced).weight(.semibold))
                                    }
                                    Text(deposit.accountName.isEmpty ? "Deposit account not set" : deposit.accountName)
                                        .foregroundStyle(AppTheme.ink3)
                                    HStack(spacing: 8) {
                                        if !deposit.reference.isEmpty {
                                            Text("Ref \(deposit.reference)")
                                        }
                                        if !deposit.memo.isEmpty {
                                            Text(deposit.memo)
                                        }
                                        Text("Open")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                                }
                                .font(.system(size: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minWidth: 360)
            }
        }
    }

    private func emptyRegisterState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed").font(.system(size: 42)).foregroundStyle(AppTheme.ink3)
            Text("Register Empty").font(.title3.bold())
            Text(message).foregroundStyle(AppTheme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func depositEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(AppTheme.ink3)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .foregroundStyle(AppTheme.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func refreshDepositContext() {
        undepositedPayments = (try? model.db.fetchUndepositedPayments()) ?? []
        recentDeposits = (try? model.db.fetchRecentDeposits()) ?? []
    }

    private func openDepositDetail(_ deposit: DepositRecordRow) {
        do {
            selectedDepositPayments = try model.db.fetchPaymentsForDeposit(depositID: deposit.id)
            selectedDeposit = deposit
        } catch {
            model.statusMessage = "Failed loading deposit detail: \(error.localizedDescription)"
        }
    }
}

private struct DepositDetailSheet: View {
    let deposit: DepositRecordRow
    let payments: [PaymentReceivedRow]

    private var paymentTotal: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deposit Detail")
                        .font(.title2.bold())
                    Text(deposit.depositDate)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(AppTheme.ink3)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatCurrency(deposit.totalAmount))
                        .font(.title3.bold())
                    Text(deposit.accountName.isEmpty ? "Deposit account not set" : deposit.accountName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }

            if !deposit.reference.isEmpty || !deposit.memo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !deposit.reference.isEmpty {
                        Text("Reference: \(deposit.reference)")
                    }
                    if !deposit.memo.isEmpty {
                        Text("Memo: \(deposit.memo)")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            }

            Divider()

            if payments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.ink3)
                    Text("No payment lines found")
                        .font(.headline)
                    Text("The deposit record exists, but no grouped payment lines were found for it.")
                        .foregroundStyle(AppTheme.ink3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    Text("Date").frame(width: 92, alignment: .leading)
                    Text("Customer").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Invoice / Receipt").frame(width: 150, alignment: .leading)
                    Text("Method").frame(width: 105, alignment: .leading)
                    Text("Amount").frame(width: 110, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ink3)

                List(payments) { payment in
                    HStack(spacing: 0) {
                        Text(payment.paymentDate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 92, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.customerDisplayName)
                            if let detail = payment.customerDisplayDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(payment.invoiceNumber.isEmpty ? "-" : payment.invoiceNumber)
                            .frame(width: 150, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(payment.method.isEmpty ? "-" : payment.method)
                            .frame(width: 105, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(formatCurrency(payment.amount))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 110, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                }

                HStack {
                    Text("\(payments.count) payment" + (payments.count == 1 ? "" : "s"))
                    Spacer()
                    Text("Line total \(formatCurrency(paymentTotal))")
                        .font(.system(size: 12, design: .monospaced).weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            }
        }
        .padding(22)
        .frame(width: 760, height: 520)
    }
}

private struct DocumentsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open, email, or share the original archived file. PDFs, images, and preserved IIF files keep their original format.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            HStack {
                TextField("Search documents", text: $model.documentSearch)
                    .textFieldStyle(.roundedBorder)
                Button("Apply") { model.refreshDocuments() }
                Button("Reset") {
                    model.documentSearch = ""
                    model.refreshDocuments()
                }
            }

            List(model.documents) { row in
                let resolvedDocumentURL = model.resolvedDocumentURL(for: row)
                let canOpenDocument = resolvedDocumentURL != nil
                HStack(spacing: 10) {
                    Text(row.category).frame(width: 140, alignment: .leading)
                    Text(row.relativePath).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Text(bytesToHuman(row.sizeBytes)).frame(width: 90, alignment: .trailing)
                    Button("Open") {
                        model.openDocument(row)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("documents.row.openButton.\(row.id)")
                    .disabled(!canOpenDocument)
                    Button("Email") {
                        model.emailDocument(row)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("documents.row.emailButton.\(row.id)")
                    .disabled(!canOpenDocument)
                    if let resolvedDocumentURL {
                        ShareLink(
                            item: resolvedDocumentURL,
                            subject: Text("Renaissance Filed document: \(row.documentFileName)"),
                            message: Text("Shared from Renaissance Filed")
                        ) {
                            Text("Share")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("documents.row.shareButton.\(row.id)")
                    } else {
                        Button("Share") {}
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("documents.row.shareButton.\(row.id)")
                            .disabled(true)
                    }
                }
                .font(.system(size: 12, weight: .regular, design: .monospaced))
            }
        }
        .padding(20)
        .onAppear { emailHarnessDocumentIfNeeded() }
    }

    private func emailHarnessDocumentIfNeeded() {
        guard let documentID = model.consumePendingEmailDocumentID(),
              let row = model.documents.first(where: { $0.id == documentID }) else {
            return
        }
        model.emailDocument(row)
    }
}

private func formatCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}

private func bytesToHuman(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var size = Double(max(0, bytes))
    var index = 0
    while size >= 1024 && index < units.count - 1 {
        size /= 1024
        index += 1
    }
    return String(format: "%.1f %@", size, units[index])
}
