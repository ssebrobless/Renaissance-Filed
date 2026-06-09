import SwiftUI

struct StartupWorkspaceView: View {
    @EnvironmentObject private var model: AppViewModel
    @StateObject private var workspace = StartupWorkspaceStore()
    @State private var showAddCustomer = false
    @State private var showWriteCheck = false
    @State private var editingCheck: ExpenseRow?

    private var bankAccounts: [AccountRow] {
        model.accounts.filter { $0.type == "asset" }
    }

    private var filteredCustomers: [CustomerRow] {
        let searched = model.customers.filter { customer in
            let query = workspace.customerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return customer.name.localizedCaseInsensitiveContains(query)
                || customer.company.localizedCaseInsensitiveContains(query)
                || customer.primaryContact.localizedCaseInsensitiveContains(query)
                || customer.phone.contains(query)
        }

        let narrowed = searched.filter { customer in
            (workspace.customerInitialFilter == "All" || entityInitialBucket(for: customer.displayName) == workspace.customerInitialFilter)
                && entityDateMatches(
                    createdAt: customer.createdAt,
                    mode: workspace.customerDateFilterMode,
                    from: workspace.customerFromDate,
                    to: workspace.customerToDate
                )
        }

        return sortEntityRows(
            narrowed,
            mode: workspace.customerSortMode,
            label: { $0.displayName },
            createdAt: { $0.createdAt }
        )
    }

    private var selectedCustomer: CustomerRow? {
        guard let customerID = workspace.selectedCustomerID else { return nil }
        return model.customers.first { $0.id == customerID }
    }

    private var registerRows: [ExpenseRow] {
        let query = workspace.registerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.expenses
            .filter { expense in
                (workspace.selectedBankAccountID == 0 || expense.paymentAccountID == workspace.selectedBankAccountID)
                    && (
                        query.isEmpty
                            || expense.displayVendorName.localizedCaseInsensitiveContains(query)
                            || expense.accountName.localizedCaseInsensitiveContains(query)
                            || expense.paymentAccountName.localizedCaseInsensitiveContains(query)
                            || expense.displayMemo.localizedCaseInsensitiveContains(query)
                            || expense.checkNumber.localizedCaseInsensitiveContains(query)
                    )
            }
            .sorted { lhs, rhs in
                if lhs.expenseDate != rhs.expenseDate { return lhs.expenseDate > rhs.expenseDate }
                if lhs.checkNumber != rhs.checkNumber { return lhs.checkNumber > rhs.checkNumber }
                return lhs.id > rhs.id
            }
    }

    private var importedRows: [TransactionRow] {
        let selectedAccountName = bankAccounts.first { $0.id == workspace.selectedBankAccountID }?.name
        let query = workspace.registerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.transactions
            .filter { row in
                (selectedAccountName == nil || row.account == selectedAccountName)
                    && (
                        query.isEmpty
                            || row.payee.localizedCaseInsensitiveContains(query)
                            || row.memo.localizedCaseInsensitiveContains(query)
                            || row.account.localizedCaseInsensitiveContains(query)
                    )
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id > rhs.id
            }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())

                if workspace.isWindowVisible(.centerPanel) {
                    StartupWorkspaceWindow(
                        title: workspace.centerMode.rawValue,
                        subtitle: "Shared launcher for customers and register",
                        layout: workspace.layout(for: .centerPanel),
                        zIndex: workspace.zIndex(for: .centerPanel),
                        onFocus: { workspace.focus(.centerPanel) },
                        onClose: { workspace.closeWindow(.centerPanel) },
                        onToggleCollapse: { workspace.toggleCollapsed(.centerPanel) },
                        onMove: { workspace.moveWindow(.centerPanel, to: $0, in: proxy.size) }
                    ) {
                        centerPanelContent
                    }
                }

                if workspace.isWindowVisible(.reportWindow) {
                    StartupWorkspaceWindow(
                        title: workspace.activeReportTab.rawValue,
                        subtitle: workspace.activeReportTab.subtitle,
                        layout: workspace.layout(for: .reportWindow),
                        zIndex: workspace.zIndex(for: .reportWindow),
                        onFocus: { workspace.focus(.reportWindow) },
                        onClose: { workspace.closeWindow(.reportWindow) },
                        onToggleCollapse: { workspace.toggleCollapsed(.reportWindow) },
                        onMove: { workspace.moveWindow(.reportWindow, to: $0, in: proxy.size) }
                    ) {
                        reportWindowContent
                            .id(reportWindowIdentity)
                    }
                }

                if workspace.isWindowVisible(.customerDetail), let selectedCustomer {
                    StartupWorkspaceWindow(
                        title: selectedCustomer.displayName,
                        subtitle: selectedCustomer.company.isEmpty ? "Customer workspace" : selectedCustomer.company,
                        layout: workspace.layout(for: .customerDetail),
                        zIndex: workspace.zIndex(for: .customerDetail),
                        onFocus: { workspace.focus(.customerDetail) },
                        onClose: { workspace.closeWindow(.customerDetail) },
                        onToggleCollapse: { workspace.toggleCollapsed(.customerDetail) },
                        onMove: { workspace.moveWindow(.customerDetail, to: $0, in: proxy.size) }
                    ) {
                        CustomerDetailSheet(customer: selectedCustomer, embedded: true) {
                            model.refreshAll()
                            reconcileSelections()
                        }
                        .id(selectedCustomer.id)
                        .environmentObject(model)
                    }
                }

                if workspace.isWindowVisible(.reportCenter) {
                    StartupWorkspaceWindow(
                        title: "Report Center",
                        subtitle: "Click a report to open or refresh the floating window",
                        layout: workspace.layout(for: .reportCenter),
                        zIndex: workspace.zIndex(for: .reportCenter),
                        onFocus: { workspace.focus(.reportCenter) },
                        onClose: { workspace.closeWindow(.reportCenter) },
                        onToggleCollapse: { workspace.toggleCollapsed(.reportCenter) },
                        onMove: { workspace.moveWindow(.reportCenter, to: $0, in: proxy.size) }
                    ) {
                        reportCenterContent
                    }
                }

                if shouldShowWorkspaceDock {
                    workspaceDock
                        .padding(.leading, 24)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                workspace.ensureWorkspaceLayout(in: proxy.size)
                reconcileSelections()
            }
            .onChange(of: proxy.size) { workspace.ensureWorkspaceLayout(in: $0) }
            .onChange(of: model.customers.map(\.id)) { _ in reconcileSelections() }
            .onChange(of: model.accounts.map(\.id)) { _ in reconcileSelections() }
            .sheet(isPresented: $showAddCustomer) {
                CustomerSheet(customer: nil) {
                    showAddCustomer = false
                    model.refreshCustomers()
                    reconcileSelections()
                    workspace.isCenterTrayExpanded = true
                }
                .environmentObject(model)
            }
            .sheet(isPresented: $showWriteCheck) {
                WriteCheckSheet(expense: nil) {
                    showWriteCheck = false
                    model.refreshExpenses()
                }
                .environmentObject(model)
            }
            .sheet(item: $editingCheck) { expense in
                WriteCheckSheet(expense: expense) {
                    editingCheck = nil
                    model.refreshExpenses()
                }
                .environmentObject(model)
            }
        }
        .accessibilityIdentifier("startup.workspace")
    }
}

private extension StartupWorkspaceView {
    var shouldShowWorkspaceDock: Bool {
        [StartupWorkspaceWindowID.centerPanel, .reportCenter, .reportWindow]
            .contains { !workspace.isWindowVisible($0) }
    }

    var centerPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Workspace", selection: $workspace.centerMode) {
                    ForEach(StartupCenterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                if workspace.centerMode == .customers {
                    Button("+ Add Customer") { showAddCustomer = true }
                        .buttonStyle(.renaissancePrimary)
                } else {
                    Button("Write Check") { showWriteCheck = true }
                        .buttonStyle(.renaissancePrimary)
                        .accessibilityIdentifier("expenses.writeCheckButton")
                }
            }

            if workspace.centerMode == .customers {
                customerControls
            } else {
                registerControls
            }

            HStack {
                Button {
                    workspace.isCenterTrayExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text("View")
                            .font(.headline)
                        Image(systemName: workspace.isCenterTrayExpanded ? "triangle.fill" : "triangle")
                            .font(.system(size: 10, weight: .bold))
                        Text(trayCountLabel)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    .foregroundStyle(AppTheme.bodyText)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(trayHelperText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            if workspace.isCenterTrayExpanded {
                Divider()
                if workspace.centerMode == .customers {
                    customerTray
                } else {
                    registerTray
                }
            } else {
                collapsedTrayHint
            }
        }
        .padding(16)
        .background(AppTheme.cardFillSoft)
    }

    var customerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Search", text: $workspace.customerSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                Picker("Order", selection: $workspace.customerSortMode) {
                    ForEach(EntityListSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Picker("Initial", selection: $workspace.customerInitialFilter) {
                    ForEach(entityInitialOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 92)

                Picker("Date", selection: $workspace.customerDateFilterMode) {
                    ForEach(EntityDateFilterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Button("Reset Filters") { workspace.resetFilters() }
                    .disabled(
                        workspace.customerSearch.isEmpty
                            && workspace.customerSortMode == .alphabeticalAsc
                            && workspace.customerInitialFilter == "All"
                            && workspace.customerDateFilterMode == .allTime
                    )
            }

            if workspace.customerDateFilterMode == .custom {
                HStack(spacing: 12) {
                    SmartDateField(date: $workspace.customerFromDate)
                    Text("to")
                        .foregroundStyle(AppTheme.ink3)
                    SmartDateField(date: $workspace.customerToDate)
                }
            }
        }
    }

    var registerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Register", selection: $workspace.registerMode) {
                    ForEach(StartupRegisterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Picker("Bank Account", selection: $workspace.selectedBankAccountID) {
                    Text("All Bank Accounts").tag(Int64(0))
                    ForEach(bankAccounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                .frame(width: 250)

                TextField("Search register", text: $workspace.registerSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Spacer()
            }
        }
    }
}

private extension StartupWorkspaceView {
    var customerTray: some View {
        Group {
            if filteredCustomers.isEmpty {
                emptyTray(icon: "person.2.slash", message: "No customers match the current filters.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredCustomers) { customer in
                            Button {
                                workspace.openCustomerWorkspace(customerID: customer.id)
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(customer.displayName)
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.bodyText)
                                        if let detail = customer.displayDetail {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.ink3)
                                        }
                                        if !customer.company.isEmpty {
                                            Text(customer.company)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.ink3)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        if !customer.phone.isEmpty {
                                            Text(customer.phone)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.ink3)
                                        }
                                        Text(String(customer.createdAt.prefix(10)))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(workspace.selectedCustomerID == customer.id ? AppTheme.panel : AppTheme.cardFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(workspace.selectedCustomerID == customer.id ? AppTheme.accent.opacity(0.55) : AppTheme.hairline, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var registerTray: some View {
        Group {
            if workspace.registerMode == .checkRegister {
                if registerRows.isEmpty {
                    emptyTray(icon: "checkbook", message: "No check activity matches the current bank account or search.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(registerRows) { expense in
                                Button {
                                    editingCheck = expense.checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : expense
                                } label: {
                                    HStack(spacing: 0) {
                                        registerCell(expense.expenseDate, width: 96, alignment: .leading)
                                        registerCell(expense.checkNumber.isEmpty ? "-" : expense.checkNumber, width: 84, alignment: .leading, monospaced: true)
                                        registerCell(expense.displayVendorName, width: 190, alignment: .leading)
                                        registerCell(expense.accountName, width: 180, alignment: .leading, secondary: true)
                                        registerCell(expense.displayMemo, width: 220, alignment: .leading, secondary: true)
                                        registerCell(currency(expense.amount), width: 110, alignment: .trailing, monospaced: true, tint: AppTheme.bad)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(AppTheme.cardFill)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(AppTheme.hairline, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("expense.row.\(expense.id)")
                            }
                        }
                        .padding(.trailing, 2)
                    }
                }
            } else if importedRows.isEmpty {
                emptyTray(icon: "arrow.down.doc", message: "No imported transactions match the current bank account or search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(importedRows) { row in
                            HStack(spacing: 0) {
                                registerCell(row.date, width: 96, alignment: .leading)
                                registerCell(row.payee, width: 200, alignment: .leading)
                                registerCell(row.account, width: 180, alignment: .leading, secondary: true)
                                registerCell(row.memo, width: 260, alignment: .leading, secondary: true)
                                registerCell(currency(row.amount), width: 110, alignment: .trailing, monospaced: true, tint: row.amount >= 0 ? AppTheme.ok : AppTheme.bad)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(AppTheme.cardFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.hairline, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func registerCell(
        _ value: String,
        width: CGFloat,
        alignment: Alignment,
        monospaced: Bool = false,
        secondary: Bool = false,
        tint: Color? = nil
    ) -> some View {
        let textColor = tint ?? (secondary ? AppTheme.secondaryText : AppTheme.bodyText)
        return Text(value.isEmpty ? "-" : value)
            .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    var collapsedTrayHint: some View {
        HStack(spacing: 10) {
            Image(systemName: workspace.centerMode == .customers ? "person.2" : "book.closed")
                .foregroundStyle(AppTheme.ink3)
            Text(workspace.centerMode == .customers
                ? "Expand View to show the customer list, or start typing to reveal it automatically."
                : "Expand View to show the register list and recent activity.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(.vertical, 10)
    }
}

private extension StartupWorkspaceView {
    var reportCenterContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    reportMetric(title: "Open AR", value: currency(model.nativeInvoices.reduce(0) { $0 + max($1.balance, 0) }))
                    reportMetric(title: "1099 Vendors", value: "\(model.vendors.filter { $0.is1099 }.count)")
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(ReportTab.allCases) { tab in
                        Button {
                            workspace.openReport(tab)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.symbolName)
                                    .frame(width: 18)
                                    .foregroundStyle(workspace.activeReportTab == tab ? AppTheme.accent : AppTheme.secondaryText)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.bodyText)
                                    Text(tab.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink3)
                                        .lineLimit(2)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(workspace.activeReportTab == tab ? AppTheme.panel : AppTheme.cardFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(workspace.activeReportTab == tab ? AppTheme.accent.opacity(0.48) : AppTheme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }

            Divider()

            HStack {
                Button("Open Window") {
                    workspace.restoreWindow(.reportWindow, expand: true)
                }
                .buttonStyle(.renaissancePrimary)
                Spacer()
                Text(workspace.activeReportTab.rawValue)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .lineLimit(1)
            }
            .padding(14)
        }
        .background(AppTheme.cardFillSoft)
    }

    @ViewBuilder
    var reportWindowContent: some View {
        switch workspace.activeReportTab {
        case .historicalPL:
            HistoricalQBPLReportView(initialYear: workspace.requestedHistoricalYear)
                .environmentObject(model)
        case .trialBalance:
            HistoricalTrialBalanceView()
                .environmentObject(model)
        case .historicalCashFlows:
            HistoricalCashFlowReportView()
                .environmentObject(model)
        case .salesByItem:
            HistoricalSalesByItemReportView()
                .environmentObject(model)
        case .operationalPL:
            PLReportView(initialPeriod: nil) { year in
                workspace.openReport(.historicalPL, requestedHistoricalYear: year)
            }
            .environmentObject(model)
        case .arAging:
            ARAgingReportView()
                .environmentObject(model)
        case .apAging:
            APAgingReportView()
                .environmentObject(model)
        case .jobProfitability:
            JobProfitabilityReportView(initialCustomerID: workspace.selectedCustomerID)
                .environmentObject(model)
        case .report1099:
            Report1099View(initialYear: workspace.requestedHistoricalYear)
                .environmentObject(model)
        case .vendorHistory:
            VendorExpenseHistoryView()
                .environmentObject(model)
        case .statement:
            CustomerStatementView(initialCustomerID: workspace.selectedCustomerID)
                .environmentObject(model)
        case .reconciliation:
            ReconciliationReportView()
                .environmentObject(model)
        }
    }

    var workspaceDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if !workspace.isWindowVisible(.centerPanel) {
                    dockButton(for: .centerPanel, title: workspace.centerMode.rawValue, forceExpand: true)
                }
                if !workspace.isWindowVisible(.reportCenter) {
                    dockButton(for: .reportCenter, title: "Report Center", forceExpand: true)
                }
                if !workspace.isWindowVisible(.reportWindow) {
                    dockButton(for: .reportWindow, title: workspace.activeReportTab.rawValue, forceExpand: false)
                }
                if let selectedCustomer, !workspace.isWindowVisible(.customerDetail) {
                    dockButton(for: .customerDetail, title: selectedCustomer.displayName, forceExpand: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.border.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
        }
        .frame(maxWidth: 820)
    }

    var trayCountLabel: String {
        switch workspace.centerMode {
        case .customers:
            return "\(filteredCustomers.count)"
        case .register:
            return "\(workspace.registerMode == .checkRegister ? registerRows.count : importedRows.count)"
        }
    }

    var trayHelperText: String {
        switch workspace.centerMode {
        case .customers:
            return "Selecting a customer opens its floating workspace."
        case .register:
            return "Switch between live check register rows and imported history."
        }
    }

    var reportWindowIdentity: String {
        [
            workspace.activeReportTab.rawValue,
            String(workspace.requestedHistoricalYear ?? -1),
            String(workspace.selectedCustomerID ?? -1),
        ].joined(separator: "|")
    }

    func reconcileSelections() {
        if let selectedCustomerID = workspace.selectedCustomerID,
           !model.customers.contains(where: { $0.id == selectedCustomerID }) {
            workspace.clearCustomerSelection()
        }

        if workspace.selectedCustomerID == nil {
            workspace.selectedCustomerID = model.customers.first?.id
        }

        if workspace.selectedBankAccountID != 0,
           !bankAccounts.contains(where: { $0.id == workspace.selectedBankAccountID }) {
            workspace.selectedBankAccountID = 0
        }
    }
}

private extension StartupWorkspaceView {
    func reportMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func dockButton(for id: StartupWorkspaceWindowID, title: String, forceExpand: Bool) -> some View {
        Button {
            workspace.restoreWindow(id, expand: forceExpand)
            workspace.focus(id)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(workspace.isWindowVisible(id) ? AppTheme.accent : AppTheme.secondaryText.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(workspace.isWindowVisible(id) ? AppTheme.panel : AppTheme.cardFillSoft)
            )
        }
        .buttonStyle(.plain)
    }

    func emptyTray(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(AppTheme.ink3)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private func currency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
