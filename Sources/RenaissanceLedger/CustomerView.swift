import SwiftUI

struct CustomersView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showAddSheet = false
    @State private var selectedCustomerID: Int64?
    @State private var search = ""
    @State private var sortMode: EntityListSortMode = .alphabeticalAsc
    @State private var initialFilter = "All"
    @State private var dateFilterMode: EntityDateFilterMode = .allTime
    @State private var customFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customToDate = Date()

    private var filtered: [CustomerRow] {
        let searched = model.customers.filter {
            guard !search.isEmpty else { return true }
            return $0.name.localizedCaseInsensitiveContains(search)
                || $0.company.localizedCaseInsensitiveContains(search)
                || $0.primaryContact.localizedCaseInsensitiveContains(search)
                || $0.phone.contains(search)
        }

        let narrowed = searched.filter { customer in
            (initialFilter == "All" || entityInitialBucket(for: customer.displayName) == initialFilter)
                && entityDateMatches(
                    createdAt: customer.createdAt,
                    mode: dateFilterMode,
                    from: customFromDate,
                    to: customToDate
                )
        }

        return sortEntityRows(
            narrowed,
            mode: sortMode,
            label: { $0.displayName },
            createdAt: { $0.createdAt }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.customers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Customers Yet").font(.title2)
                    Text("Add your first customer to start creating invoices.").foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 240)
                    Divider()
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityIdentifier("customers.root")
        .onAppear {
            openHarnessCustomerIfNeeded()
            ensureSelection()
        }
        .onChange(of: filtered.map(\.id)) { _ in
            ensureSelection()
        }
        .sheet(isPresented: $showAddSheet) {
            CustomerSheet(customer: nil) {
                showAddSheet = false
                model.refreshCustomers()
                ensureSelection()
            }
            .environmentObject(model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Customer Center")
                        .font(.title2.bold())
                    Text("Browse customers on the left and work their estimates, invoices, payments, and history on the right.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                Button("+ Add Customer") { showAddSheet = true }
                    .accessibilityIdentifier("customers.addButton")
            }

            HStack(spacing: 12) {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                Picker("Order", selection: $sortMode) {
                    ForEach(EntityListSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("Initial", selection: $initialFilter) {
                    ForEach(entityInitialOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Picker("Date", selection: $dateFilterMode) {
                    ForEach(EntityDateFilterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Button("Reset Filters") {
                    search = ""
                    sortMode = .alphabeticalAsc
                    initialFilter = "All"
                    dateFilterMode = .allTime
                    customFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                    customToDate = Date()
                }
                .disabled(
                    search.isEmpty
                        && sortMode == .alphabeticalAsc
                        && initialFilter == "All"
                        && dateFilterMode == .allTime
                )
            }

            if dateFilterMode == .custom {
                HStack(spacing: 12) {
                    SmartDateField(date: $customFromDate)
                    Text("to")
                        .foregroundStyle(AppTheme.ink3)
                    SmartDateField(date: $customToDate)
                }
            }
        }
        .padding()
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customers")
                    .font(.headline)
                Spacer()
                Text("\(filtered.count)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            List(filtered, selection: $selectedCustomerID) { c in
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.displayName).font(.headline)
                        if let detail = c.displayDetail {
                            Text(detail).font(.caption).foregroundStyle(AppTheme.ink3)
                        }
                        if !c.company.isEmpty {
                            Text(c.company).font(.subheadline).foregroundStyle(AppTheme.ink3)
                        }
                        if !c.primaryContact.isEmpty {
                            Text(c.primaryContact).font(.caption).foregroundStyle(AppTheme.ink3)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if !c.phone.isEmpty { Text(c.phone).font(.caption) }
                        if !c.city.isEmpty {
                            Text(c.city + (c.state.isEmpty ? "" : ", " + c.state))
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .accessibilityIdentifier("customer.row.\(c.id)")
                .tag(c.id)
            }
            .accessibilityIdentifier("customers.list")
        }
        .background(AppTheme.canvas)
    }

    private var detailPane: some View {
        Group {
            if let customer = selectedCustomer {
                CustomerDetailSheet(customer: customer, embedded: true) {
                    model.refreshAll()
                    ensureSelection()
                }
                .id(customer.id)
                .environmentObject(model)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 42))
                        .foregroundStyle(AppTheme.ink3)
                    Text("Select a customer")
                        .font(.title3.bold())
                    Text("Customer details, estimates, invoices, and payments will appear here.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedCustomer: CustomerRow? {
        guard let selectedCustomerID else { return nil }
        return model.customers.first(where: { $0.id == selectedCustomerID })
    }

    private func openHarnessCustomerIfNeeded() {
        guard selectedCustomerID == nil,
              let customerID = model.peekPendingCustomerID(),
              model.customers.contains(where: { $0.id == customerID })
        else { return }
        model.selectedTab = .customers
        selectedCustomerID = customerID
        model.clearPendingCustomerID(customerID)
    }

    private func ensureSelection() {
        if selectedCustomerID == nil {
            selectedCustomerID = filtered.first?.id
            return
        }
        if let selectedCustomerID,
           !filtered.contains(where: { $0.id == selectedCustomerID }) {
            self.selectedCustomerID = filtered.first?.id
        }
    }
}

private enum CustomerDetailModal: String, Identifiable {
    case edit
    case newEstimate
    case newInvoice
    case newSalesReceipt
    case receivePayment
    case customerCredit

    var id: String { rawValue }
}

private enum CustomerDetailRoute: Identifiable {
    case modal(CustomerDetailModal)
    case detailEstimate(EstimateRow)
    case editEstimate(EstimateRow)
    case duplicateEstimate(EstimateRow)
    case changeOrderEstimate(EstimateRow)
    case invoiceFromEstimate(EstimateRow, EstimateInvoiceProgressSelection)
    case detailInvoice(NativeInvoiceRow)
    case editInvoice(NativeInvoiceRow)
    case duplicateInvoice(NativeInvoiceRow)
    case detailSalesReceipt(SalesReceiptRow)
    case editSalesReceipt(SalesReceiptRow)
    case duplicateSalesReceipt(SalesReceiptRow)

    var id: String {
        switch self {
        case let .modal(modal):
            return "modal:\(modal.id)"
        case let .detailEstimate(estimate):
            return "detail-estimate:\(estimate.id)"
        case let .editEstimate(estimate):
            return "edit-estimate:\(estimate.id)"
        case let .duplicateEstimate(estimate):
            return "duplicate-estimate:\(estimate.id)"
        case let .changeOrderEstimate(estimate):
            return "change-order-estimate:\(estimate.id)"
        case let .invoiceFromEstimate(estimate, selection):
            return "invoice-from-estimate:\(estimate.id):\(selection.mode.rawValue):\(selection.percentDisplayValue)"
        case let .detailInvoice(invoice):
            return "detail-invoice:\(invoice.id)"
        case let .editInvoice(invoice):
            return "edit-invoice:\(invoice.id)"
        case let .duplicateInvoice(invoice):
            return "duplicate-invoice:\(invoice.id)"
        case let .detailSalesReceipt(receipt):
            return "detail-sales-receipt:\(receipt.id)"
        case let .editSalesReceipt(receipt):
            return "edit-sales-receipt:\(receipt.id)"
        case let .duplicateSalesReceipt(receipt):
            return "duplicate-sales-receipt:\(receipt.id)"
        }
    }
}

struct CustomerDetailSheet: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var currentCustomer: CustomerRow
    @State private var snapshot = CustomerActivitySnapshot(
        openBalance: 0,
        estimateCount: 0,
        estimateTotal: 0,
        invoiceCount: 0,
        invoiceTotal: 0,
        paymentCount: 0,
        paymentTotal: 0
    )
    @State private var estimates: [EstimateRow] = []
    @State private var estimateProgressByID: [Int64: EstimateProgressSnapshot] = [:]
    @State private var invoices: [NativeInvoiceRow] = []
    @State private var salesReceipts: [SalesReceiptRow] = []
    @State private var payments: [PaymentReceivedRow] = []
    @State private var availableCredits: [CustomerCreditRow] = []
    @State private var statement: [CustomerStatementLine] = []
    @State private var jobs: [JobRow] = []
    @State private var activeRoute: CustomerDetailRoute?
    @State private var showNewJobSheet = false
    @State private var editingJob: JobRow?
    @State private var showInvoiceStartChooser = false
    @State private var progressInvoiceEstimate: EstimateRow?
    @Environment(\.dismiss) private var dismiss

    private let embedded: Bool
    var onChange: () -> Void

    init(customer: CustomerRow, embedded: Bool = false, onChange: @escaping () -> Void) {
        self.embedded = embedded
        self.onChange = onChange
        _currentCustomer = State(initialValue: customer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentCustomer.displayName)
                        .font(.title2.bold())
                    if let detail = currentCustomer.displayDetail {
                        Text(detail)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !currentCustomer.company.isEmpty {
                        Text(currentCustomer.company)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !currentCustomer.primaryContact.isEmpty {
                        Text(currentCustomer.primaryContact)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !currentCustomer.address.isEmpty {
                        Text(currentCustomer.address)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !mailingLine.isEmpty {
                        Text(mailingLine)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !contactLine.isEmpty {
                        Text(contactLine)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
                Spacer()
                Button("Edit Customer") { activeRoute = .modal(.edit) }
                    .accessibilityIdentifier("customer.detail.editCustomerButton")
                Button("New Estimate") { activeRoute = .modal(.newEstimate) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.detail.newEstimateButton")
                Button("New Invoice") { beginInvoiceWorkflow() }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("customer.detail.newInvoiceButton")
                Button("New Sales Receipt") { activeRoute = .modal(.newSalesReceipt) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.detail.newSalesReceiptButton")
                Button("Receive Payment") { activeRoute = .modal(.receivePayment) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.detail.receivePaymentButton")
                if !embedded {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("customer.detail.doneButton")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summaryCards
                    quickActionsSection
                    jobsSection
                    activitySection
                    estimatesSection
                    invoicesSection
                    salesReceiptsSection
                    paymentsSection
                    creditsSection
                }
                .padding(20)
            }
        }
        .frame(
            minWidth: embedded ? 640 : 980,
            maxWidth: .infinity,
            minHeight: embedded ? 640 : 720,
            maxHeight: .infinity
        )
        .onAppear {
            loadData()
            scheduleHarnessRouteIfNeeded()
        }
        .accessibilityIdentifier("customer.detail.\(currentCustomer.id)")
        .sheet(item: $activeRoute) { route in
            switch route {
            case let .modal(modal):
                customerModalView(for: modal)
            case let .detailEstimate(estimate):
                EstimateDetailSheet(estimate: estimate) {
                    activeRoute = nil
                    model.refreshEstimates()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
            case let .editEstimate(estimate):
                NewEstimateSheet(estimate: estimate) {
                    model.refreshEstimates()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .duplicateEstimate(estimate):
                NewEstimateSheet(duplicateSource: estimate) {
                    model.refreshEstimates()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .changeOrderEstimate(estimate):
                NewEstimateSheet(changeOrderSource: estimate) {
                    model.refreshEstimates()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .invoiceFromEstimate(estimate, selection):
                NewInvoiceSheet(
                    prefilledCustomerID: currentCustomer.id,
                    sourceEstimate: estimate,
                    sourceEstimateProgressSelection: selection
                ) {
                    model.refreshNativeInvoices()
                    model.refreshEstimates()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .detailInvoice(invoice):
                InvoiceDetailSheet(invoice: invoice) {
                    activeRoute = nil
                    model.refreshNativeInvoices()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
            case let .editInvoice(invoice):
                NewInvoiceSheet(invoice: invoice) {
                    model.refreshNativeInvoices()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .duplicateInvoice(invoice):
                NewInvoiceSheet(duplicateSource: invoice) {
                    model.refreshNativeInvoices()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .detailSalesReceipt(receipt):
                SalesReceiptDetailSheet(receipt: receipt) {
                    activeRoute = nil
                    model.refreshSalesReceipts()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
            case let .editSalesReceipt(receipt):
                SalesReceiptSheet(receipt: receipt) {
                    model.refreshSalesReceipts()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            case let .duplicateSalesReceipt(receipt):
                SalesReceiptSheet(duplicateSource: receipt) {
                    model.refreshSalesReceipts()
                    loadData()
                    onChange()
                    activeRoute = nil
                }
                .environmentObject(model)
            }
        }
        .sheet(isPresented: $showInvoiceStartChooser) {
            CustomerInvoiceStartChooserSheet(
                customerName: currentCustomer.displayName,
                openEstimates: openEstimates,
                onChooseBlank: {
                    showInvoiceStartChooser = false
                    activeRoute = .modal(.newInvoice)
                },
                onChooseEstimate: { estimate in
                    showInvoiceStartChooser = false
                    beginEstimateInvoiceWorkflow(estimate)
                }
            )
        }
        .sheet(isPresented: $showNewJobSheet) {
            JobSheet(customer: currentCustomer, job: nil) {
                showNewJobSheet = false
                model.refreshJobs()
                loadData()
                onChange()
            }
            .environmentObject(model)
        }
        .sheet(item: $editingJob) { job in
            JobSheet(customer: currentCustomer, job: job) {
                editingJob = nil
                model.refreshJobs()
                loadData()
                onChange()
            }
            .environmentObject(model)
        }
        .sheet(item: $progressInvoiceEstimate) { estimate in
            EstimateInvoiceProgressChooserSheet(
                estimate: estimate,
                progress: estimateProgress(for: estimate),
                loadLines: { try model.db.fetchEstimateLines(estimateID: estimate.id) },
                onStart: { selection in
                    progressInvoiceEstimate = nil
                    activeRoute = .invoiceFromEstimate(estimate, selection)
                }
            )
        }
    }

    @ViewBuilder
    private func customerModalView(for modal: CustomerDetailModal) -> some View {
        switch modal {
        case .edit:
                CustomerSheet(customer: currentCustomer) {
                    activeRoute = nil
                    model.refreshCustomers()
                    refreshCurrentCustomer()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
        case .newEstimate:
                NewEstimateSheet(prefilledCustomerID: currentCustomer.id) {
                    activeRoute = nil
                    model.refreshEstimates()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
        case .newInvoice:
                NewInvoiceSheet(prefilledCustomerID: currentCustomer.id) {
                    activeRoute = nil
                    model.refreshNativeInvoices()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
        case .newSalesReceipt:
                SalesReceiptSheet(prefilledCustomerID: currentCustomer.id) {
                    activeRoute = nil
                    model.refreshSalesReceipts()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
        case .receivePayment:
                ReceivePaymentSheet(prefilledCustomerID: currentCustomer.id) {
                    activeRoute = nil
                    model.refreshNativeInvoices()
                    loadData()
                    onChange()
                }
                .environmentObject(model)
        case .customerCredit:
                CustomerCreditSheet(prefilledCustomerID: currentCustomer.id) {
                    activeRoute = nil
                    loadData()
                    onChange()
                }
                .environmentObject(model)
        }
    }

    private var contactLine: String {
        [currentCustomer.phone, currentCustomer.email]
            .filter { !$0.isEmpty }
            .joined(separator: "  |  ")
    }

    private var mailingLine: String {
        [currentCustomer.city, currentCustomer.state, currentCustomer.zip]
            .filter { !$0.isEmpty }
            .joined(separator: currentCustomer.zip.isEmpty ? ", " : " ")
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            customerSummaryCard(
                title: "Open Balance",
                value: customerCurrency(snapshot.openBalance),
                actionLabel: "Open Statement"
            ) {
                model.openCustomerStatementReport(customerID: currentCustomer.id)
            }
            customerSummaryCard(title: "Estimates", value: "\(snapshot.estimateCount) / \(customerCurrency(snapshot.estimateTotal))")
            customerSummaryCard(title: "Invoices", value: "\(snapshot.invoiceCount) / \(customerCurrency(snapshot.invoiceTotal))")
            customerSummaryCard(title: "Payments", value: "\(snapshot.paymentCount) / \(customerCurrency(snapshot.paymentTotal))")
            customerSummaryCard(title: "Credits", value: "\(snapshot.availableCreditCount) / \(customerCurrency(snapshot.availableCreditTotal))")
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                Button("New Estimate") { activeRoute = .modal(.newEstimate) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.quick.newEstimateButton")

                if let latestEstimate {
                    Button("New From Last Estimate") { activeRoute = .changeOrderEstimate(latestEstimate) }
                        .buttonStyle(.renaissanceSecondary)
                        .accessibilityIdentifier("customer.quick.changeOrderEstimateButton")
                }

                Button("New Invoice") { beginInvoiceWorkflow() }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("customer.quick.newInvoiceButton")

                Button("New Sales Receipt") { activeRoute = .modal(.newSalesReceipt) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.quick.newSalesReceiptButton")

                Button("Receive Payment") { activeRoute = .modal(.receivePayment) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.quick.receivePaymentButton")

                Button("Add Job") { showNewJobSheet = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.quick.addJobButton")

                Button("Add Credit") { activeRoute = .modal(.customerCredit) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.quick.addCreditButton")

                if !openEstimates.isEmpty {
                    Button(openEstimates.count == 1 ? "Invoice Open Estimate" : "Choose Open Estimate") {
                        showInvoiceStartChooser = true
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.quick.invoiceOpenEstimateButton")
                }

                if let latestInvoice {
                    Button("Duplicate Last Invoice") { activeRoute = .duplicateInvoice(latestInvoice) }
                        .buttonStyle(.renaissanceSecondary)
                        .accessibilityIdentifier("customer.quick.duplicateInvoiceButton")
                }

                Button("Statement Report") {
                    model.openCustomerStatementReport(customerID: currentCustomer.id)
                }
                .buttonStyle(.renaissanceSecondary)
                .accessibilityIdentifier("customer.quick.statementReportButton")

                Button("Report Center") {
                    model.openCustomerReportCenter(customerID: currentCustomer.id)
                }
                .buttonStyle(.renaissanceSecondary)
                .accessibilityIdentifier("customer.quick.reportCenterButton")
            }

            if !openEstimates.isEmpty {
                Text(openEstimates.count == 1
                     ? "This customer has 1 open estimate ready to invoice."
                     : "This customer has \(openEstimates.count) open estimates ready to invoice.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Jobs")
                    .font(.headline)
                Spacer()
                Button("Add Job") { showNewJobSheet = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.jobs.addButton")
            }

            if jobs.isEmpty {
                customerEmptyState(message: "No jobs for this customer yet.")
            } else {
                VStack(spacing: 0) {
                    customerTableHeader([
                        ("Job", 220),
                        ("Status", 110),
                        ("Site", 250),
                        ("Actions", 160)
                    ])

                    ForEach(jobs) { job in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.name)
                                if !job.displayNotes.isEmpty {
                                    Text(job.displayNotes)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink3)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 220, alignment: .leading)
                            Text(job.status.capitalized)
                                .foregroundStyle(job.isActive ? .primary : .secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(job.siteAddress.isEmpty ? "-" : job.siteAddress)
                                .foregroundStyle(AppTheme.ink3)
                                .lineLimit(1)
                                .frame(width: 250, alignment: .leading)
                            HStack(spacing: 8) {
                                Button("Edit") { editingJob = job }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.job.edit.\(job.id)")
                                Button("Profitability") {
                                    model.openReportCenter(tab: "jobprofitability", customerID: currentCustomer.id)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("customer.job.report.\(job.id)")
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(.leading, 12)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.headline)

            if statement.isEmpty {
                customerEmptyState(message: "No customer activity recorded.")
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Date").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                        Text("Type").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .leading)
                        Text("Reference").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Amount").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .trailing)
                        Text("Balance").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(AppTheme.surface)

                    Divider()

                    ForEach(statement) { line in
                        HStack(spacing: 0) {
                            Text(line.date)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            Text(line.type)
                                .frame(width: 120, alignment: .leading)
                            Text(line.reference.isEmpty ? "-" : line.reference)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(line.type == "Estimate" ? "-" : customerCurrency(line.amount))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.amount < 0 ? AppTheme.ok : .primary)
                                .frame(width: 120, alignment: .trailing)
                            Text(customerCurrency(line.balance))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { openActivity(line) }
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var estimatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimates")
                .font(.headline)

            if estimates.isEmpty {
                customerEmptyState(message: "No estimates for this customer.")
            } else {
                VStack(spacing: 0) {
                    customerTableHeader([
                        ("Date", 100),
                        ("Estimate #", 120),
                        ("Status", 110),
                        ("Total", 120),
                        ("Actions", 240)
                    ])

                    ForEach(estimates) { estimate in
                        HStack(spacing: 0) {
                            Text(estimate.issueDate).font(.system(size: 12, design: .monospaced)).frame(width: 100, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(estimate.estimateNumber).font(.system(size: 12, design: .monospaced))
                                if estimate.hasJob {
                                    Text(estimate.jobName)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink3)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 120, alignment: .leading)
                            Text(estimateStatusLabel(for: estimate))
                                .foregroundStyle(estimateStatusTint(for: estimate))
                                .frame(width: 110, alignment: .leading)
                            Text(customerCurrency(estimate.total)).font(.system(size: 12, design: .monospaced)).frame(width: 120, alignment: .trailing)
                            HStack(spacing: 8) {
                                Button("Open") { showEstimateDetail(estimate) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.estimate.open.\(estimate.id)")
                                Button("Edit") { showEstimateEditor(estimate) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.estimate.edit.\(estimate.id)")
                                if estimateProgress(for: estimate).hasRemainingBalance {
                                    Button("Invoice") { beginEstimateInvoiceWorkflow(estimate) }
                                        .buttonStyle(.borderless)
                                        .accessibilityIdentifier("customer.estimate.invoice.\(estimate.id)")
                                }
                                if latestLinkedInvoice(for: estimate) != nil {
                                    Button("Latest Invoice") {
                                        if let invoice = latestLinkedInvoice(for: estimate) {
                                            showInvoiceDetail(invoice)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.estimate.linkedInvoice.\(estimate.id)")
                                }
                            }
                            .frame(width: 240, alignment: .leading)
                            .padding(.leading, 12)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { showEstimateDetail(estimate) }
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invoices")
                .font(.headline)

            if invoices.isEmpty {
                customerEmptyState(message: "No invoices for this customer.")
            } else {
                VStack(spacing: 0) {
                    customerTableHeader([
                        ("Date", 100),
                        ("Invoice #", 120),
                        ("Status", 110),
                        ("Total", 120),
                        ("Balance", 120),
                        ("Actions", 160)
                    ])

                    ForEach(invoices) { invoice in
                        HStack(spacing: 0) {
                            Text(invoice.issueDate).font(.system(size: 12, design: .monospaced)).frame(width: 100, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invoice.invoiceNumber).font(.system(size: 12, design: .monospaced))
                                if invoice.hasJob {
                                    Text(invoice.jobName)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink3)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 120, alignment: .leading)
                            Text(invoice.status.capitalized).foregroundStyle(invoice.balance > 0 ? AppTheme.warn : AppTheme.ok).frame(width: 110, alignment: .leading)
                            Text(customerCurrency(invoice.total)).font(.system(size: 12, design: .monospaced)).frame(width: 120, alignment: .trailing)
                            Text(customerCurrency(invoice.balance)).font(.system(size: 12, design: .monospaced)).frame(width: 120, alignment: .trailing)
                            HStack(spacing: 8) {
                                Button("Open") { showInvoiceDetail(invoice) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.invoice.open.\(invoice.id)")
                                Button("Edit") { showInvoiceEditor(invoice) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.invoice.edit.\(invoice.id)")
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(.leading, 12)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { showInvoiceDetail(invoice) }
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var salesReceiptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sales Receipts")
                    .font(.headline)
                Spacer()
                Button("New Sales Receipt") { activeRoute = .modal(.newSalesReceipt) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.salesReceipts.newButton")
            }

            if salesReceipts.isEmpty {
                customerEmptyState(message: "No sales receipts for this customer.")
            } else {
                VStack(spacing: 0) {
                    customerTableHeader([
                        ("Date", 100),
                        ("Receipt #", 120),
                        ("Method", 120),
                        ("Deposit", 170),
                        ("Total", 120),
                        ("Actions", 180)
                    ])

                    ForEach(salesReceipts) { receipt in
                        HStack(spacing: 0) {
                            Text(receipt.receiptDate).font(.system(size: 12, design: .monospaced)).frame(width: 100, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.receiptNumber).font(.system(size: 12, design: .monospaced))
                                if receipt.hasJob {
                                    Text(receipt.jobName)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink3)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 120, alignment: .leading)
                            Text(receipt.paymentMethodLabel).frame(width: 120, alignment: .leading)
                            Text(receipt.depositAccountLabel)
                                .foregroundStyle(AppTheme.ink3)
                                .frame(width: 170, alignment: .leading)
                            Text(customerCurrency(receipt.total)).font(.system(size: 12, design: .monospaced)).foregroundStyle(AppTheme.ok).frame(width: 120, alignment: .trailing)
                            HStack(spacing: 8) {
                                Button("Open") { showSalesReceiptDetail(receipt) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.salesReceipt.open.\(receipt.id)")
                                Button("Edit") { showSalesReceiptEditor(receipt) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("customer.salesReceipt.edit.\(receipt.id)")
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding(.leading, 12)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { showSalesReceiptDetail(receipt) }
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Payments")
                    .font(.headline)
                Spacer()
                Button("Receive Payment") { activeRoute = .modal(.receivePayment) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.payments.receiveButton")
            }

            if payments.isEmpty {
                customerEmptyState(message: "No payments for this customer.")
            } else {
                VStack(spacing: 0) {
                    customerTableHeader([
                        ("Date", 100),
                        ("Method", 110),
                        ("Invoice #", 120),
                        ("Reference", 180),
                        ("Amount", 120)
                    ])

                    ForEach(payments) { payment in
                        HStack(spacing: 0) {
                            Text(payment.paymentDate).font(.system(size: 12, design: .monospaced)).frame(width: 100, alignment: .leading)
                            Text(payment.method.capitalized).frame(width: 110, alignment: .leading)
                            Text(payment.invoiceNumber.isEmpty ? "-" : payment.invoiceNumber).font(.system(size: 12, design: .monospaced)).frame(width: 120, alignment: .leading)
                            Text(payment.reference.isEmpty ? "-" : payment.reference).frame(width: 180, alignment: .leading)
                            Text(customerCurrency(payment.amount)).font(.system(size: 12, design: .monospaced)).foregroundStyle(AppTheme.ok).frame(width: 120, alignment: .trailing)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Credits")
                    .font(.headline)
                Spacer()
                Button("Add Credit") { activeRoute = .modal(.customerCredit) }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("customer.credits.addButton")
            }

            if availableCredits.isEmpty {
                customerEmptyState(message: "No available credits for this customer.")
            } else {
                VStack(spacing: 0) {
                    customerTableHeader([
                        ("Date", 100),
                        ("Type", 120),
                        ("Reference", 180),
                        ("Original", 120),
                        ("Remaining", 120)
                    ])

                    ForEach(availableCredits) { credit in
                        HStack(spacing: 0) {
                            Text(credit.creditDate)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            Text(credit.creditType.capitalized)
                                .frame(width: 120, alignment: .leading)
                            Text(credit.reference.isEmpty ? "-" : credit.reference)
                                .frame(width: 180, alignment: .leading)
                            Text(customerCurrency(credit.amount))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 120, alignment: .trailing)
                            Text(customerCurrency(credit.remainingAmount))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AppTheme.ok)
                                .frame(width: 120, alignment: .trailing)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private func loadData() {
        refreshCurrentCustomer()
        snapshot = (try? model.db.fetchCustomerActivitySnapshot(customerID: currentCustomer.id)) ?? snapshot
        estimates = (try? model.db.fetchCustomerEstimates(customerID: currentCustomer.id)) ?? []
        estimateProgressByID = (try? model.db.fetchEstimateProgressSnapshots(estimateIDs: estimates.map(\.id))) ?? [:]
        invoices = (try? model.db.fetchCustomerInvoices(customerID: currentCustomer.id)) ?? []
        salesReceipts = (try? model.db.fetchCustomerSalesReceipts(customerID: currentCustomer.id)) ?? []
        payments = (try? model.db.fetchPaymentsForCustomer(customerID: currentCustomer.id)) ?? []
        availableCredits = (try? model.db.fetchCustomerCredits(customerID: currentCustomer.id)) ?? []
        jobs = (try? model.db.fetchJobs(customerID: currentCustomer.id, includeInactive: true)) ?? []
        statement = (try? model.db.fetchCustomerStatement(customerID: currentCustomer.id)) ?? []
        openHarnessDetailIfNeeded()
    }

    private func openHarnessDetailIfNeeded() {
        if let estimateID = model.peekPendingEstimateID(),
           let estimate = estimates.first(where: { $0.id == estimateID }) ?? (try? model.db.fetchEstimate(id: estimateID)) {
            DispatchQueue.main.async {
                showEstimateDetail(estimate)
            }
            model.clearPendingEstimateID(estimateID)
        }

        if let invoiceID = model.peekPendingInvoiceID(),
           let invoice = invoices.first(where: { $0.id == invoiceID }) ?? (try? model.db.fetchInvoice(id: invoiceID)) {
            DispatchQueue.main.async {
                showInvoiceDetail(invoice)
            }
            model.clearPendingInvoiceID(invoiceID)
        }
    }

    private func scheduleHarnessRouteIfNeeded() {
        if let estimateID = model.peekPendingEditEstimateID(),
           let estimate = estimates.first(where: { $0.id == estimateID }) ?? (try? model.db.fetchEstimate(id: estimateID)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                showEstimateEditor(estimate)
                model.clearPendingEditEstimateID(estimateID)
            }
        }

        if let invoiceID = model.peekPendingEditInvoiceID(),
           let invoice = invoices.first(where: { $0.id == invoiceID }) ?? (try? model.db.fetchInvoice(id: invoiceID)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                showInvoiceEditor(invoice)
                model.clearPendingEditInvoiceID(invoiceID)
            }
        }
    }

    private func showEstimateDetail(_ estimate: EstimateRow) {
        activeRoute = .detailEstimate(estimate)
    }

    private func showEstimateEditor(_ estimate: EstimateRow) {
        activeRoute = .editEstimate(estimate)
    }

    private func showInvoiceDetail(_ invoice: NativeInvoiceRow) {
        activeRoute = .detailInvoice(invoice)
    }

    private func showInvoiceEditor(_ invoice: NativeInvoiceRow) {
        activeRoute = .editInvoice(invoice)
    }

    private func beginInvoiceWorkflow() {
        if openEstimates.isEmpty {
            activeRoute = .modal(.newInvoice)
        } else if openEstimates.count == 1, let estimate = openEstimates.first {
            beginEstimateInvoiceWorkflow(estimate)
        } else {
            showInvoiceStartChooser = true
        }
    }

    private func beginEstimateInvoiceWorkflow(_ estimate: EstimateRow) {
        progressInvoiceEstimate = estimate
    }

    private func refreshCurrentCustomer() {
        if let refreshed = model.customers.first(where: { $0.id == currentCustomer.id }) {
            currentCustomer = refreshed
        }
    }

    private func openActivity(_ line: CustomerStatementLine) {
        switch line.type {
        case "Estimate":
            if let estimate = estimates.first(where: { $0.estimateNumber == line.reference }) {
                showEstimateDetail(estimate)
            }
        case "Invoice":
            if let invoice = invoices.first(where: { $0.invoiceNumber == line.reference }) {
                showInvoiceDetail(invoice)
            }
        case "Sales Receipt":
            if let receipt = salesReceipts.first(where: { $0.receiptNumber == line.reference }) {
                showSalesReceiptDetail(receipt)
            }
        default:
            break
        }
    }

    private func showSalesReceiptDetail(_ receipt: SalesReceiptRow) {
        activeRoute = .detailSalesReceipt(receipt)
    }

    private func showSalesReceiptEditor(_ receipt: SalesReceiptRow) {
        activeRoute = .editSalesReceipt(receipt)
    }

    private func customerSummaryCard(title: String, value: String, actionLabel: String? = nil, onTap: (() -> Void)? = nil) -> some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    customerSummaryCardContent(title: title, value: value, actionLabel: actionLabel)
                }
                .buttonStyle(.plain)
            } else {
                customerSummaryCardContent(title: title, value: value, actionLabel: actionLabel)
            }
        }
    }

    private func customerSummaryCardContent(title: String, value: String, actionLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(AppTheme.ink3)
            Text(value).font(.title3.bold())
            if let actionLabel {
                Text(actionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline, lineWidth: 1))
        .cornerRadius(8)
    }

    private var openEstimates: [EstimateRow] {
        estimates.filter { estimate in
            let normalizedStatus = estimate.status.lowercased()
            return normalizedStatus != "void"
                && normalizedStatus != "inactive"
                && estimateProgress(for: estimate).hasRemainingBalance
        }
    }

    private var latestEstimate: EstimateRow? {
        estimates.first
    }

    private var latestInvoice: NativeInvoiceRow? {
        invoices.first
    }

    private func estimateProgress(for estimate: EstimateRow) -> EstimateProgressSnapshot {
        estimateProgressByID[estimate.id] ?? .empty(estimateID: estimate.id, estimateTotal: estimate.total)
    }

    private func latestLinkedInvoice(for estimate: EstimateRow) -> NativeInvoiceRow? {
        let invoiceID = estimateProgress(for: estimate).latestInvoiceID != 0
            ? estimateProgress(for: estimate).latestInvoiceID
            : estimate.linkedInvoiceID
        guard invoiceID != 0 else { return nil }
        return invoices.first(where: { $0.id == invoiceID })
    }

    private func estimateStatusLabel(for estimate: EstimateRow) -> String {
        let progress = estimateProgress(for: estimate)
        if progress.linkedInvoiceCount > 0 && progress.hasRemainingBalance {
            return "Partial"
        }
        return estimate.status.capitalized
    }

    private func estimateStatusTint(for estimate: EstimateRow) -> Color {
        let progress = estimateProgress(for: estimate)
        if progress.linkedInvoiceCount > 0 && progress.hasRemainingBalance {
            return .orange
        }
        return estimateStatusColor(estimate.status)
    }

    private func customerEmptyState(message: String) -> some View {
        Text(message)
            .foregroundStyle(AppTheme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.surface)
            .cornerRadius(8)
    }

    private func customerTableHeader(_ columns: [(String, CGFloat)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { item in
                Text(item.element.0)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink3)
                    .frame(width: item.element.1, alignment: .leading)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
    }
}

private struct JobSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let customer: CustomerRow
    let job: JobRow?
    var onSave: () -> Void

    @State private var name = ""
    @State private var status = "active"
    @State private var siteAddress = ""
    @State private var notes = ""
    @State private var isActive = true
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    private let statusOptions = ["prospect", "active", "completed", "warranty", "inactive"]
    private var isEditing: Bool { job != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? "Edit Job" : "Add Job")
                        .font(.title2.bold())
                    Text(customer.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.bad)
                }
            }
            .padding()

            Divider()

            Form {
                Section("Job Details") {
                    TextField("Job Name", text: $name)
                    Picker("Status", selection: $status) {
                        ForEach(statusOptions, id: \.self) { option in
                            Text(option.capitalized).tag(option)
                        }
                    }
                    Toggle("Active Job", isOn: $isActive)
                }

                Section("Site") {
                    TextField("Site Address", text: $siteAddress, axis: .vertical)
                        .lineLimit(2...3)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isEditing ? "Save Changes" : "Save Job") { saveJob() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .onAppear(perform: setup)
    }

    private func setup() {
        guard let job else { return }
        name = job.name
        status = job.status
        siteAddress = job.siteAddress
        notes = job.notes
        isActive = job.isActive
    }

    private func saveJob() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a job name."
            return
        }

        do {
            if let job {
                try model.db.updateJob(
                    id: job.id,
                    name: trimmedName,
                    status: status,
                    siteAddress: siteAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    isActive: isActive
                )
            } else {
                _ = try model.db.insertJob(
                    customerID: customer.id,
                    name: trimmedName,
                    status: status,
                    siteAddress: siteAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    isActive: isActive
                )
            }
            onSave()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

private struct CustomerInvoiceStartChooserSheet: View {
    let customerName: String
    let openEstimates: [EstimateRow]
    let onChooseBlank: () -> Void
    let onChooseEstimate: (EstimateRow) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Invoice")
                        .font(.title2.bold())
                    Text(customerName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink3)
                    Text("QuickBooks usually surfaces open estimates here before starting a blank invoice.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        dismiss()
                        onChooseBlank()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start Blank Invoice")
                                .font(.headline)
                            Text("Skip estimate conversion and build a fresh invoice for this customer.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppTheme.surface)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customer.invoiceChooser.blankButton")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(openEstimates.count == 1 ? "Open Estimate" : "Open Estimates")
                            .font(.headline)

                        ForEach(openEstimates) { estimate in
                            Button {
                                dismiss()
                                onChooseEstimate(estimate)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Estimate \(estimate.estimateNumber)")
                                            .font(.headline)
                                        Text("\(estimate.issueDate)  |  \(customerCurrency(estimate.total))")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                        if !estimate.displayMemo.isEmpty {
                                            Text(estimate.displayMemo)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.ink3)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Text("Use Estimate")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(AppTheme.canvas)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("customer.invoiceChooser.estimate.\(estimate.id)")
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 620, height: 420)
    }
}

struct CustomerSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let customer: CustomerRow?
    var onSave: () -> Void

    @State private var name = ""
    @State private var company = ""
    @State private var primaryContact = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { customer != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Customer" : "Add Customer")
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                Section("Contact") {
                    TextField("Full Name *", text: $name)
                    TextField("Company", text: $company)
                    TextField("Primary Contact", text: $primaryContact)
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
                }
                Section("Address") {
                    TextField("Street Address", text: $address)
                    HStack {
                        TextField("City", text: $city)
                        TextField("State", text: $state).frame(width: 80)
                        TextField("ZIP", text: $zip).frame(width: 100)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isEditing ? "Save Changes" : "Save Customer") { save() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 480)
        .onAppear {
            if let c = customer {
                name = c.name
                company = c.company
                primaryContact = c.primaryContact
                email = c.email
                phone = c.phone
                address = c.address
                city = c.city
                state = c.state
                zip = c.zip
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let c = customer {
            model.updateCustomer(id: c.id, name: trimmed, company: company, primaryContact: primaryContact, email: email,
                                 phone: phone, address: address, city: city, state: state, zip: zip)
        } else {
            model.addCustomer(name: trimmed, company: company, primaryContact: primaryContact, email: email, phone: phone,
                              address: address, city: city, state: state, zip: zip)
        }
        onSave()
    }
}

private func customerCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
