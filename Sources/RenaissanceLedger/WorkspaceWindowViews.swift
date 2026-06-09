import SwiftUI

extension WorkspaceWindowManager {
    @ViewBuilder
    func rootView(for kind: WorkspaceWindowKind) -> some View {
        switch kind {
        case .center:
            WorkspaceCenterWindowView()
        case .reportCenter:
            WorkspaceReportCenterWindowView()
        case .report:
            WorkspaceReportWindowView()
        case .customer:
            WorkspaceCustomerWindowView()
        case .navigator:
            WorkspaceNavigatorWindowView()
        case .checkDesk:
            CheckDeskWindowView()
        case .help:
            HelpMeWindowView()
        case .techSupport:
            TechSupportWindowView()
        case .claudeControl:
            ClaudeControlWindowView()
        }
    }
}

struct WorkspaceNavigatorWindowView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            if model.selectedTab == .workspace {
                WorkspaceNavigatorLauncherView()
            } else {
                ContentView()
            }
        }
    }
}

private struct WorkspaceNavigatorLauncherView: View {
    @EnvironmentObject private var windowManager: WorkspaceWindowManager

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("Navigation")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.bodyText)
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(NavigatorRoute.primary, id: \.self) { route in
                    Button(route.compactLabel) {
                        windowManager.openNavigatorRoute(route.tab)
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("workspace.navigator.launcher.\(route.tab.rawValue)")
                }
            }

            HStack(spacing: 6) {
                Button("Customer / Register") {
                    windowManager.showCenterWindow()
                }
                .buttonStyle(.renaissanceSecondary)
                .controlSize(.small)

                Button("Report Center") {
                    windowManager.showReportCenterWindow()
                }
                .buttonStyle(.renaissanceSecondary)
                .controlSize(.small)
            }
            .font(.caption)

            HStack(spacing: 6) {
                Button {
                    windowManager.showHelpWindow()
                } label: {
                    Label("Help Me", systemImage: "questionmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.renaissancePrimary)
                .controlSize(.small)
                .accessibilityIdentifier("workspace.navigator.launcher.helpMe")

                Button {
                    windowManager.showTechSupportWindow()
                } label: {
                    Label("Tech Support", systemImage: "wrench.and.screwdriver.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.renaissancePrimary)
                .controlSize(.small)
                .accessibilityIdentifier("workspace.navigator.launcher.techSupport")
            }
        }
        .padding(8)
        .frame(width: 292, height: 186)
        .clipped()
        .background(AppTheme.surface)
    }
}

struct WorkspaceLauncherView: View {
    @EnvironmentObject private var windowManager: WorkspaceWindowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace Windows")
                    .font(.system(size: 28, weight: .bold))
                Text("The launch workspace now opens as native macOS windows instead of one giant host screen.")
                    .foregroundStyle(AppTheme.ink3)
            }

            HStack(spacing: 12) {
                Button("Show Customer Center / Register") {
                    windowManager.showCenterWindow()
                }
                .buttonStyle(.renaissancePrimary)

                Button("Show Report Center") {
                    windowManager.showReportCenterWindow()
                }
                .buttonStyle(.renaissanceSecondary)

                Button("Pop Out Report Window") {
                    windowManager.showReportWindow()
                }
                .buttonStyle(.renaissanceSecondary)
            }

            Text("Use the other tabs in this navigator for secondary workflows. The main QB-style launch experience lives in the floating workspace windows.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
    }
}

struct WorkspaceCustomerWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @EnvironmentObject private var session: WorkspaceSession
    @EnvironmentObject private var windowManager: WorkspaceWindowManager

    private var selectedCustomer: CustomerRow? {
        guard let customerID = session.selectedCustomerID else { return nil }
        return model.customers.first { $0.id == customerID }
    }

    var body: some View {
        Group {
            if let selectedCustomer {
                CustomerDetailSheet(customer: selectedCustomer, embedded: true) {
                    model.refreshAll()
                }
                .id(selectedCustomer.id)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 38))
                        .foregroundStyle(AppTheme.ink3)
                    Text("No customer selected")
                        .font(.title3.bold())
                    Text("Choose a customer from the Customer Center window to open its workspace here.")
                        .foregroundStyle(AppTheme.ink3)
                        .multilineTextAlignment(.center)
                    Button("Show Customer Center") {
                        windowManager.showCenterWindow()
                    }
                    .buttonStyle(.renaissancePrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
        .background(AppTheme.surface)
    }
}

struct WorkspaceReportWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @EnvironmentObject private var session: WorkspaceSession
    @EnvironmentObject private var windowManager: WorkspaceWindowManager

    var body: some View {
        Group {
            switch session.activeReportTab {
            case .historicalPL:
                HistoricalQBPLReportView(initialYear: session.requestedHistoricalYear)
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
                    windowManager.openReport(tab: .historicalPL, customerID: session.selectedCustomerID, requestedHistoricalYear: year)
                }
                .environmentObject(model)
            case .arAging:
                ARAgingReportView()
                    .environmentObject(model)
            case .apAging:
                APAgingReportView()
                    .environmentObject(model)
            case .jobProfitability:
                JobProfitabilityReportView(initialCustomerID: session.selectedCustomerID)
                    .environmentObject(model)
            case .report1099:
                Report1099View(initialYear: session.requestedHistoricalYear)
                    .environmentObject(model)
            case .vendorHistory:
                VendorExpenseHistoryView()
                    .environmentObject(model)
            case .statement:
                CustomerStatementView(initialCustomerID: session.selectedCustomerID)
                    .environmentObject(model)
            case .reconciliation:
                ReconciliationReportView()
                    .environmentObject(model)
            }
        }
        .id([
            session.activeReportTab.rawValue,
            String(session.requestedHistoricalYear ?? -1),
            String(session.selectedCustomerID ?? -1),
        ].joined(separator: "|"))
        .background(AppTheme.surface)
    }
}

struct WorkspaceReportCenterWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @EnvironmentObject private var session: WorkspaceSession
    @EnvironmentObject private var windowManager: WorkspaceWindowManager

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        workspaceReportMetric(title: "Open AR", value: workspaceCurrency(model.nativeInvoices.reduce(0) { $0 + max($1.balance, 0) }))
                        workspaceReportMetric(title: "1099 Vendors", value: "\(model.vendors.filter { $0.is1099 }.count)")
                    }

                    HStack(spacing: 10) {
                        Text("Report Center")
                            .font(.title3.bold())

                        Button {
                            windowManager.setReportViewerExpanded(!session.isReportViewerExpanded)
                        } label: {
                            HStack(spacing: 6) {
                                Text(session.isReportViewerExpanded ? "View" : "Expand")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: session.isReportViewerExpanded ? "triangle.fill" : "triangle")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(AppTheme.bodyText)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .padding(14)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(ReportTab.allCases) { tab in
                            Button {
                                windowManager.openReport(tab: tab, customerID: session.selectedCustomerID)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: tab.symbolName)
                                        .frame(width: 18)
                                        .foregroundStyle(session.activeReportTab == tab ? AppTheme.accent : AppTheme.secondaryText)

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
                                        .fill(session.activeReportTab == tab ? AppTheme.panel : AppTheme.cardFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(session.activeReportTab == tab ? AppTheme.accent.opacity(0.48) : AppTheme.hairline, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }

                Divider()

                HStack {
                    Button("Show Customer Center") {
                        windowManager.showCenterWindow()
                    }
                    .buttonStyle(.renaissanceSecondary)

                    Spacer()

                    Button("Pop Out") {
                        windowManager.showReportWindow()
                    }
                    .buttonStyle(.renaissancePrimary)
                }
                .padding(14)
            }
            .frame(width: 290)
            .background(AppTheme.surface)

            if session.isReportViewerExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.activeReportTab.rawValue)
                                .font(.title3.bold())
                            Text(session.activeReportTab.subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }

                        Spacer()

                        Button("Pop Out") {
                            windowManager.showReportWindow()
                        }
                        .buttonStyle(.renaissanceSecondary)

                        Button {
                            windowManager.setReportViewerExpanded(false)
                        } label: {
                            Label("Collapse", systemImage: "sidebar.right")
                        }
                        .buttonStyle(.renaissanceSecondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    Divider()

                    WorkspaceReportWindowView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
            }
        }
        .background(AppTheme.surface)
    }
}

struct WorkspaceCenterWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @EnvironmentObject private var session: WorkspaceSession
    @EnvironmentObject private var windowManager: WorkspaceWindowManager
    @State private var showAddCustomer = false
    @State private var editingCheck: ExpenseRow?

    private var bankAccounts: [AccountRow] {
        model.accounts.filter { $0.type == "asset" }
    }

    private var filteredCustomers: [CustomerRow] {
        let searched = model.customers.filter { customer in
            let query = session.customerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return customer.name.localizedCaseInsensitiveContains(query)
                || customer.company.localizedCaseInsensitiveContains(query)
                || customer.primaryContact.localizedCaseInsensitiveContains(query)
                || customer.phone.contains(query)
        }

        let narrowed = searched.filter { customer in
            (session.customerInitialFilter == "All" || entityInitialBucket(for: customer.displayName) == session.customerInitialFilter)
                && entityDateMatches(
                    createdAt: customer.createdAt,
                    mode: session.customerDateFilterMode,
                    from: session.customerFromDate,
                    to: session.customerToDate
                )
        }

        return sortEntityRows(
            narrowed,
            mode: session.customerSortMode,
            label: { $0.displayName },
            createdAt: { $0.createdAt }
        )
    }

    private var registerRows: [ExpenseRow] {
        let query = session.registerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.expenses
            .filter { expense in
                (session.selectedBankAccountID == 0 || expense.paymentAccountID == session.selectedBankAccountID)
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
        let selectedAccountName = bankAccounts.first { $0.id == session.selectedBankAccountID }?.name
        let query = session.registerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Workspace", selection: $session.centerMode) {
                    ForEach(StartupCenterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                Button("Show Report Center") {
                    windowManager.showReportCenterWindow()
                }
                .buttonStyle(.renaissanceSecondary)

                if session.centerMode == .customers {
                    Button("+ Add Customer") { showAddCustomer = true }
                        .buttonStyle(.renaissancePrimary)
                } else {
                    Button("Write Check") { windowManager.showCheckDeskForNewCheck() }
                        .buttonStyle(.renaissancePrimary)
                        .accessibilityIdentifier("expenses.writeCheckButton")
                }
            }

            if session.centerMode == .customers {
                customerControls
            } else {
                registerControls
            }

            HStack {
                Button {
                    session.isCenterTrayExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text("View")
                            .font(.headline)
                        Image(systemName: session.isCenterTrayExpanded ? "triangle.fill" : "triangle")
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

            if session.isCenterTrayExpanded {
                Divider()
                if session.centerMode == .customers {
                    customerTray
                } else {
                    registerTray
                }
            } else {
                collapsedTrayHint
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .onAppear {
            if session.selectedCustomerID == nil {
                session.selectedCustomerID = model.customers.first?.id
            }
        }
        .sheet(isPresented: $showAddCustomer) {
            CustomerSheet(customer: nil) {
                showAddCustomer = false
                model.refreshCustomers()
                session.selectedCustomerID = model.customers.first?.id
                session.isCenterTrayExpanded = true
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

    private var customerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Search", text: $session.customerSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                Picker("Order", selection: $session.customerSortMode) {
                    ForEach(EntityListSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Picker("Initial", selection: $session.customerInitialFilter) {
                    ForEach(entityInitialOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 92)

                Picker("Date", selection: $session.customerDateFilterMode) {
                    ForEach(EntityDateFilterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Button("Reset Filters") { session.resetCustomerFilters() }
                    .disabled(
                        session.customerSearch.isEmpty
                            && session.customerSortMode == .alphabeticalAsc
                            && session.customerInitialFilter == "All"
                            && session.customerDateFilterMode == .allTime
                    )
            }

            if session.customerDateFilterMode == .custom {
                HStack(spacing: 12) {
                    SmartDateField(date: $session.customerFromDate)
                    Text("to")
                        .foregroundStyle(AppTheme.ink3)
                    SmartDateField(date: $session.customerToDate)
                }
            }
        }
    }

    private var registerControls: some View {
        HStack(spacing: 12) {
            Picker("Register", selection: $session.registerMode) {
                ForEach(StartupRegisterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Picker("Bank Account", selection: $session.selectedBankAccountID) {
                Text("All Bank Accounts").tag(Int64(0))
                ForEach(bankAccounts) { account in
                    Text(account.name).tag(account.id)
                }
            }
            .frame(width: 250)

            TextField("Search register", text: $session.registerSearch)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Spacer()
        }
    }

    private var customerTray: some View {
        Group {
            if filteredCustomers.isEmpty {
                workspaceEmptyTray(icon: "person.2.slash", message: "No customers match the current filters.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredCustomers) { customer in
                            Button {
                                windowManager.openCustomerWorkspace(customerID: customer.id)
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
                                        .fill(session.selectedCustomerID == customer.id ? AppTheme.panel : AppTheme.cardFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(session.selectedCustomerID == customer.id ? AppTheme.accent.opacity(0.55) : AppTheme.hairline, lineWidth: 1)
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

    private var registerTray: some View {
        Group {
            if session.registerMode == .checkRegister {
                if registerRows.isEmpty {
                    workspaceEmptyTray(icon: "checkbook", message: "No check activity matches the current bank account or search.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(registerRows) { expense in
                                Button {
                                    if expense.checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        editingCheck = nil
                                    } else {
                                        windowManager.showCheckDesk(for: expense)
                                    }
                                } label: {
                                    HStack(spacing: 0) {
                                        workspaceRegisterCell(expense.expenseDate, width: 96, alignment: .leading)
                                        workspaceRegisterCell(expense.checkNumber.isEmpty ? "-" : expense.checkNumber, width: 84, alignment: .leading, monospaced: true)
                                        workspaceRegisterCell(expense.displayVendorName, width: 190, alignment: .leading)
                                        workspaceRegisterCell(expense.accountName, width: 180, alignment: .leading, secondary: true)
                                        workspaceRegisterCell(expense.displayMemo, width: 220, alignment: .leading, secondary: true)
                                        workspaceRegisterCell(workspaceCurrency(expense.amount), width: 110, alignment: .trailing, monospaced: true, tint: AppTheme.bad)
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
                workspaceEmptyTray(icon: "arrow.down.doc", message: "No imported transactions match the current bank account or search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(importedRows) { row in
                            HStack(spacing: 0) {
                                workspaceRegisterCell(row.date, width: 96, alignment: .leading)
                                workspaceRegisterCell(row.payee, width: 200, alignment: .leading)
                                workspaceRegisterCell(row.account, width: 180, alignment: .leading, secondary: true)
                                workspaceRegisterCell(row.memo, width: 260, alignment: .leading, secondary: true)
                                workspaceRegisterCell(workspaceCurrency(row.amount), width: 110, alignment: .trailing, monospaced: true, tint: row.amount >= 0 ? AppTheme.ok : AppTheme.bad)
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

    private var trayCountLabel: String {
        switch session.centerMode {
        case .customers:
            return "\(filteredCustomers.count)"
        case .register:
            return "\(session.registerMode == .checkRegister ? registerRows.count : importedRows.count)"
        }
    }

    private var trayHelperText: String {
        switch session.centerMode {
        case .customers:
            return "Selecting a customer opens its own native workspace window."
        case .register:
            return "Switch between live check register rows and imported history."
        }
    }

    private var collapsedTrayHint: some View {
        HStack(spacing: 10) {
            Image(systemName: session.centerMode == .customers ? "person.2" : "book.closed")
                .foregroundStyle(AppTheme.ink3)
            Text(session.centerMode == .customers
                ? "Expand View to show the customer list, or start typing to reveal it automatically."
                : "Expand View to show the register list and recent activity.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(.vertical, 10)
    }
}

private func workspaceReportMetric(title: String, value: String) -> some View {
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

private func workspaceCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}

private func workspaceRegisterCell(
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

private func workspaceEmptyTray(icon: String, message: String) -> some View {
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
