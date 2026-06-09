import AppKit
import SwiftUI

enum ReportSourceKind {
    case historicalQB
    case liveOperational
    case hybridReview

    var title: String {
        switch self {
        case .historicalQB: return "Historical QB"
        case .liveOperational: return "Live Operational"
        case .hybridReview: return "Hybrid / Review"
        }
    }

    var shortTitle: String {
        switch self {
        case .historicalQB: return "QB"
        case .liveOperational: return "Live"
        case .hybridReview: return "Hybrid"
        }
    }

    var color: Color {
        switch self {
        case .historicalQB: return AppTheme.accent
        case .liveOperational: return AppTheme.ok
        case .hybridReview: return AppTheme.warn
        }
    }
}

enum ReportTab: String, CaseIterable, Codable, Identifiable {
    case historicalPL = "Historical QB P&L"
    case trialBalance = "Trial Balance"
    case historicalCashFlows = "Historical QB Cash Flows"
    case salesByItem = "Sales By Item"
    case operationalPL = "Operational Cash Summary"
    case arAging = "A/R Aging"
    case apAging = "A/P Aging"
    case jobProfitability = "Job Profitability"
    case report1099 = "1099 Summary"
    case vendorHistory = "Payee Spend"
    case statement = "Customer Statements"
    case reconciliation = "Bank Reconciliation"
    var id: String { rawValue }

    var sourceKind: ReportSourceKind {
        switch self {
        case .historicalPL, .trialBalance, .historicalCashFlows, .salesByItem:
            return .historicalQB
        case .operationalPL, .arAging, .apAging, .jobProfitability, .vendorHistory, .statement, .reconciliation:
            return .liveOperational
        case .report1099:
            return .hybridReview
        }
    }

    var subtitle: String {
        switch self {
        case .historicalPL:
            return "Authoritative historical QuickBooks profit and loss"
        case .trialBalance:
            return "Historical QuickBooks trial balance snapshot"
        case .historicalCashFlows:
            return "Historical QuickBooks statement of cash flows snapshot"
        case .salesByItem:
            return "Historical QuickBooks sales by item summary"
        case .operationalPL:
            return "Day-to-day cash-style view only; use Historical QB P&L for QuickBooks-matching historical numbers"
        case .arAging:
            return "Open receivables by aging bucket"
        case .apAging:
            return "Unpaid bills owed to vendors by aging bucket"
        case .jobProfitability:
            return "Compare estimates, invoices, balances, and expenses by job"
        case .report1099:
            return "Historical snapshots and optional live-year 1099 review"
        case .vendorHistory:
            return "Searchable payee and vendor expense history"
        case .statement:
            return "Printable customer account history"
        case .reconciliation:
            return "Completed bank reconciliations and cleared items"
        }
    }

    var symbolName: String {
        switch self {
        case .historicalPL: return "building.columns"
        case .trialBalance: return "list.clipboard"
        case .historicalCashFlows: return "chart.line.text.clipboard"
        case .salesByItem: return "shippingbox"
        case .operationalPL: return "chart.bar.xaxis"
        case .arAging: return "clock.arrow.circlepath"
        case .apAging: return "creditcard.trianglebadge.exclamationmark"
        case .jobProfitability: return "briefcase"
        case .report1099: return "doc.text.magnifyingglass"
        case .vendorHistory: return "person.2.badge.gearshape"
        case .statement: return "person.text.rectangle"
        case .reconciliation: return "checkmark.seal"
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var activeTab = ReportTab.historicalPL
    @State private var harnessReportYear: Int?
    @State private var harnessReportPeriod: String?
    @State private var pendingReportCustomerID: Int64?
    @State private var requestedHistoricalYear: Int?

    var body: some View {
        HSplitView {
            reportSidebar
                .frame(minWidth: 270, idealWidth: 300, maxWidth: 340)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Report Center")
                                .font(.title2.bold())
                            ReportSourceBadge(kind: activeTab.sourceKind)
                        }
                        Text(activeTab.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Spacer()
                }
                .padding()

                Divider()

                switch activeTab {
                case .historicalPL:
                    HistoricalQBPLReportView(initialYear: requestedHistoricalYear ?? harnessReportYear)
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
                    PLReportView(initialPeriod: harnessReportPeriod) { year in
                        requestedHistoricalYear = year
                        activeTab = .historicalPL
                    }
                        .environmentObject(model)
                case .arAging:
                    ARAgingReportView()
                        .environmentObject(model)
                case .apAging:
                    APAgingReportView()
                        .environmentObject(model)
                case .jobProfitability:
                    JobProfitabilityReportView(initialCustomerID: pendingReportCustomerID)
                        .environmentObject(model)
                case .report1099:
                    Report1099View(initialYear: harnessReportYear)
                        .environmentObject(model)
                case .vendorHistory:
                    VendorExpenseHistoryView()
                        .environmentObject(model)
                case .statement:
                    CustomerStatementView(initialCustomerID: pendingReportCustomerID)
                        .environmentObject(model)
                case .reconciliation:
                    ReconciliationReportView()
                        .environmentObject(model)
                }
            }
            .background(AppTheme.surface)
        }
        .accessibilityIdentifier("reports.root")
        .onAppear {
            if let pendingTab = model.peekPendingReportTab(),
               let resolvedTab = reportTab(from: pendingTab) {
                activeTab = resolvedTab
            }
            harnessReportYear = model.peekPendingReportYear()
            harnessReportPeriod = model.peekPendingReportPeriod()
            pendingReportCustomerID = model.peekPendingReportCustomerID()
            requestedHistoricalYear = harnessReportYear
            model.clearPendingReportRoute()
        }
    }

    private func reportTab(from rawValue: String) -> ReportTab? {
        if let exact = ReportTab.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }) {
            return exact
        }

        switch rawValue.lowercased() {
        case "historical", "historicalpl", "historical_qb_pl", "historical_qb_p&l":
            return .historicalPL
        case "trialbalance", "trial_balance":
            return .trialBalance
        case "historicalcashflows", "historical_cash_flows", "cashflows", "cash_flows":
            return .historicalCashFlows
        case "salesbyitem", "sales_by_item":
            return .salesByItem
        case "operational", "operationalpl", "operational_cash_pl", "operational_cash_summary":
            return .operationalPL
        case "araging", "ar_aging":
            return .arAging
        case "apaging", "ap_aging", "payables":
            return .apAging
        case "jobprofitability", "job_profitability", "jobs", "jobreport":
            return .jobProfitability
        case "1099", "1099summary", "report1099":
            return .report1099
        case "vendor", "vendorhistory", "vendor_spend", "vendorspend":
            return .vendorHistory
        case "statement", "customerstatement", "customer_statements":
            return .statement
        case "reconciliation", "bankreconciliation", "bank_reconciliation", "reconcile":
            return .reconciliation
        default:
            return nil
        }
    }

    private var reportSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reports")
                    .font(.headline)
                HStack(spacing: 12) {
                    reportMetric("Open AR", value: rptCurrency(model.nativeInvoices.reduce(0) { $0 + max($1.balance, 0) }))
                    reportMetric("1099 Vendors", value: "\(model.vendors.filter { $0.is1099 }.count)")
                }
            }
            .padding(16)

            Divider()

            ForEach(ReportTab.allCases) { tab in
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.symbolName)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tab.rawValue)
                                    .font(.headline)
                                ReportSourceBadge(kind: tab.sourceKind, compact: true)
                            }
                            Text(tab.subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(activeTab == tab ? AppTheme.accent.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }

            Spacer()
        }
        .background(AppTheme.canvas)
    }

    private func reportMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - P&L

struct PLReportView: View {
    @EnvironmentObject private var model: AppViewModel
    let initialPeriod: String?
    let openHistoricalYear: (Int) -> Void
    @State private var selectedPeriod = "this_year"
    @State private var customFrom = Date()
    @State private var customTo = Date()
    @State private var report: PLReport?
    @State private var isLoading = false
    @State private var historicalYears: Set<Int> = []

    let periods = [
        ("this_year", "This Year"),
        ("last_year", "Last Year"),
        ("this_quarter", "This Quarter"),
        ("all_time", "All Time"),
        ("custom", "Custom Range"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(periods, id: \.0) { p in Text(p.1).tag(p.0) }
                }
                .frame(width: 160)
                if selectedPeriod == "custom" {
                    HStack(spacing: 4) {
                        Text("From").foregroundStyle(AppTheme.ink3)
                        SmartDateField(date: $customFrom)
                    }
                    HStack(spacing: 4) {
                        Text("To").foregroundStyle(AppTheme.ink3)
                        SmartDateField(date: $customTo)
                    }
                }
                Button("Run Report") { generateReport() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(isLoading)
            }
            .padding()

            Divider()

            if let r = report {
                plReportBody(r)
            } else {
                emptyState(icon: "chart.bar", message: "Select a period and click Run Report.")
            }
        }
        .onAppear {
            historicalYears = Set((try? model.db.fetchHistoricalPLYears()) ?? [])
            if let initialPeriod,
               periods.contains(where: { $0.0 == initialPeriod }) {
                selectedPeriod = initialPeriod
            }
            if report == nil && !isLoading {
                generateReport()
            }
        }
    }

    private func plReportBody(_ r: PLReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operational Cash Summary (Not Historical QB P&L)").font(.title.bold())
                    Text("Your Company Name").font(.headline).foregroundStyle(AppTheme.ink3)
                    Text("\(r.fromDate) through \(r.toDate)").font(.subheadline).foregroundStyle(AppTheme.ink3)
                    Text("This is a day-to-day cash-style summary based on recorded payments and expense entries. It is not the authoritative historical QuickBooks profit and loss. Use Historical QB P&L whenever you want QuickBooks-matching historical income, COGS, and expenses.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                .padding(.bottom, 8)

                if let historicalYear = matchingHistoricalYear(for: r) {
                    historicalWarningCard(year: historicalYear)
                }

                ReportSection(title: "INCOME", lines: r.incomeLines, total: r.totalIncome,
                              totalLabel: "Total Income", color: AppTheme.ok)
                ReportSection(title: "EXPENSES", lines: r.expenseLines, total: r.totalExpenses,
                              totalLabel: "Total Expenses", color: AppTheme.bad)

                Divider()
                HStack {
                    Text("NET INCOME").font(.title3.bold())
                    Spacer()
                    Text(rptCurrency(r.netIncome))
                        .font(.title3.bold())
                        .foregroundStyle(r.netIncome >= 0 ? AppTheme.ok : AppTheme.bad)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface))
            }
            .padding(24)
            .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func historicalWarningCard(year: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Historical QuickBooks data is available for \(year).", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.warn)
            Text("This cash summary is useful for day-to-day operations, but imported checks, credit-card activity, and timing differences can make it diverge from the original QuickBooks profit and loss for historical years.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink3)
            Button("Open Historical QB P&L for \(year)") {
                openHistoricalYear(year)
            }
            .buttonStyle(.renaissancePrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private func matchingHistoricalYear(for report: PLReport) -> Int? {
        let fromParts = report.fromDate.split(separator: "-")
        let toParts = report.toDate.split(separator: "-")
        guard fromParts.count == 3,
              toParts.count == 3,
              fromParts[0] == toParts[0],
              fromParts[1] == "01",
              fromParts[2] == "01",
              toParts[1] == "12",
              toParts[2] == "31",
              let year = Int(fromParts[0]),
              historicalYears.contains(year) else {
            return nil
        }
        return year
    }

    private func generateReport() {
        isLoading = true
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var from: String
        var to: String
        switch selectedPeriod {
        case "this_year":
            let y = cal.component(.year, from: now)
            from = "\(y)-01-01"; to = "\(y)-12-31"
        case "last_year":
            let y = cal.component(.year, from: now) - 1
            from = "\(y)-01-01"; to = "\(y)-12-31"
        case "this_quarter":
            let month = cal.component(.month, from: now)
            let year = cal.component(.year, from: now)
            let qStart = ((month - 1) / 3) * 3 + 1
            let qEnd = min(qStart + 2, 12)
            from = String(format: "%04d-%02d-01", year, qStart)
            let lastDay = cal.range(of: .day, in: .month, for: cal.date(from: DateComponents(year: year, month: qEnd))!)!.count
            to = String(format: "%04d-%02d-%02d", year, qEnd, lastDay)
        case "custom":
            from = fmt.string(from: customFrom)
            to = fmt.string(from: customTo)
        default:
            from = "2000-01-01"; to = "2099-12-31"
        }
        do {
            report = try model.db.fetchPLReport(from: from, to: to)
        } catch {
            model.statusMessage = "Report error: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct HistoricalQBPLReportView: View {
    @EnvironmentObject private var model: AppViewModel
    let initialYear: Int?
    @State private var availableYears: [Int] = []
    @State private var selectedYear = Calendar.current.component(.year, from: Date()) - 1
    @State private var report: HistoricalPLReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Year:").foregroundStyle(AppTheme.ink3)
                Picker("Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .frame(width: 120)
                .labelsHidden()
                .disabled(availableYears.isEmpty)
                Button("Run Report") { loadReport() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(availableYears.isEmpty)
            }
            .padding()

            Divider()

            if availableYears.isEmpty {
                emptyState(icon: "building.columns", message: "No historical QuickBooks P&L snapshots have been loaded yet.")
            } else if let report {
                historicalPLBody(report)
            } else {
                emptyState(icon: "building.columns", message: "Select a historical year and click Run Report.")
            }
        }
        .onAppear {
            reloadReportIfPossible()
            if availableYears.isEmpty {
                scheduleHistoricalReloadRetry(remaining: 4)
            }
        }
    }

    private func historicalPLBody(_ report: HistoricalPLReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Historical QB Profit & Loss").font(.title.bold())
                    Text("Your Company Name").font(.headline).foregroundStyle(AppTheme.ink3)
                    Text("January through December \(report.year)").font(.subheadline).foregroundStyle(AppTheme.ink3)
                    Text("Authoritative historical QuickBooks P&L imported from the QB general ledger snapshots.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                .padding(.bottom, 8)

                ReportSection(
                    title: "INCOME",
                    lines: report.incomeLines,
                    total: report.totalIncome,
                    totalLabel: "Total Income",
                    color: AppTheme.ok
                )
                ReportSection(
                    title: "COST OF GOODS SOLD",
                    lines: report.cogsLines,
                    total: report.totalCOGS,
                    totalLabel: "Total COGS",
                    color: AppTheme.warn
                )

                HStack {
                    Text("GROSS PROFIT").font(.title3.bold())
                    Spacer()
                    Text(rptCurrency(report.grossProfit))
                        .font(.title3.bold())
                        .foregroundStyle(report.grossProfit >= 0 ? AppTheme.ok : AppTheme.bad)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface))

                ReportSection(
                    title: "EXPENSES",
                    lines: report.expenseLines,
                    total: report.totalExpenses,
                    totalLabel: "Total Expenses",
                    color: AppTheme.bad
                )

                Divider()
                HStack {
                    Text("NET INCOME").font(.title3.bold())
                    Spacer()
                    Text(rptCurrency(report.netIncome))
                        .font(.title3.bold())
                        .foregroundStyle(report.netIncome >= 0 ? AppTheme.ok : AppTheme.bad)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface))
            }
            .padding(24)
            .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadYears() {
        availableYears = (try? model.db.fetchHistoricalPLYears()) ?? []
        if let firstYear = availableYears.first, !availableYears.contains(selectedYear) {
            selectedYear = firstYear
        }
    }

    private func loadReport() {
        if availableYears.isEmpty {
            report = nil
            return
        }
        report = try? model.db.fetchHistoricalPLReport(year: selectedYear)
    }

    private func reloadReportIfPossible() {
        loadYears()
        if let initialYear, availableYears.contains(initialYear) {
            selectedYear = initialYear
        }
        loadReport()
    }

    private func scheduleHistoricalReloadRetry(remaining: Int) {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            reloadReportIfPossible()
            if availableYears.isEmpty || report == nil {
                scheduleHistoricalReloadRetry(remaining: remaining - 1)
            }
        }
    }
}

struct HistoricalTrialBalanceView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var report: HistoricalTrialBalanceReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Run Report") { loadReport() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            Divider()

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Historical QB Trial Balance").font(.title.bold())
                            Text("Your Company Name").font(.headline).foregroundStyle(AppTheme.ink3)
                            Text(report.asOfLabel).font(.subheadline).foregroundStyle(AppTheme.ink3)
                            Text("Imported from preserved QuickBooks trial balance source.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }

                        HStack(spacing: 0) {
                            Text("Account")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Debit")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)
                                .frame(width: 140, alignment: .trailing)
                            Text("Credit")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)
                                .frame(width: 140, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface)

                        ForEach(report.lines) { line in
                            HStack(spacing: 0) {
                                Text(line.accountName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(line.debit == 0 ? "-" : rptCurrency(line.debit))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 140, alignment: .trailing)
                                Text(line.credit == 0 ? "-" : rptCurrency(line.credit))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 140, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            Divider()
                        }

                        HStack {
                            Text("TOTAL").font(.title3.bold())
                            Spacer()
                            Text(rptCurrency(report.totalDebit))
                                .font(.title3.bold())
                                .frame(width: 140, alignment: .trailing)
                            Text(rptCurrency(report.totalCredit))
                                .font(.title3.bold())
                                .frame(width: 140, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface))
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                }
                .frame(maxWidth: .infinity)
            } else {
                emptyState(icon: "list.clipboard", message: "No historical QuickBooks trial balance has been loaded yet.")
            }
        }
        .onAppear {
            if report == nil {
                loadReport()
            }
        }
    }

    private func loadReport() {
        report = try? model.db.fetchHistoricalTrialBalanceReport()
    }
}

struct HistoricalCashFlowReportView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var report: HistoricalCashFlowReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Run Report") { loadReport() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            Divider()

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Historical QB Statement Of Cash Flows").font(.title.bold())
                            Text("Your Company Name").font(.headline).foregroundStyle(AppTheme.ink3)
                            Text(report.asOfLabel).font(.subheadline).foregroundStyle(AppTheme.ink3)
                            Text("Imported from preserved QuickBooks cash flow source.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }

                        ForEach(report.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.headline)
                                    .textCase(.uppercase)
                                ForEach(section.lines) { line in
                                    HStack {
                                        Text(line.label)
                                        Spacer()
                                        Text(rptCurrency(line.total))
                                            .font(.system(size: 12, design: .monospaced))
                                    }
                                    .padding(.vertical, 2)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                }
                .frame(maxWidth: .infinity)
            } else {
                emptyState(icon: "chart.line.text.clipboard", message: "No historical QuickBooks cash flow report has been loaded yet.")
            }
        }
        .onAppear {
            if report == nil {
                loadReport()
            }
        }
    }

    private func loadReport() {
        report = try? model.db.fetchHistoricalCashFlowReport()
    }
}

struct HistoricalSalesByItemReportView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var report: HistoricalSalesByItemReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Run Report") { loadReport() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            Divider()

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Historical QB Sales By Item Summary").font(.title.bold())
                            Text("Your Company Name").font(.headline).foregroundStyle(AppTheme.ink3)
                            Text(report.periodLabel).font(.subheadline).foregroundStyle(AppTheme.ink3)
                            Text("Imported from preserved QuickBooks sales-by-item summary source.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }

                        ForEach(report.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.headline)
                                HStack(spacing: 0) {
                                    Text("Item")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Qty")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.ink3)
                                        .frame(width: 90, alignment: .trailing)
                                    Text("Amount")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.ink3)
                                        .frame(width: 120, alignment: .trailing)
                                    Text("% Sales")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.ink3)
                                        .frame(width: 90, alignment: .trailing)
                                    Text("Avg Price")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.ink3)
                                        .frame(width: 100, alignment: .trailing)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(AppTheme.surface)

                                ForEach(section.lines) { line in
                                    HStack(spacing: 0) {
                                        Text(line.itemName)
                                            .font(line.isSubtotal ? .headline : .body)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(line.quantity == 0 ? "-" : String(format: "%.2f", line.quantity))
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(width: 90, alignment: .trailing)
                                        Text(rptCurrency(line.amount))
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(width: 120, alignment: .trailing)
                                        Text(line.percentOfSales == 0 ? "-" : String(format: "%.1f%%", line.percentOfSales))
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(width: 90, alignment: .trailing)
                                        Text(line.averagePrice == 0 ? "-" : rptCurrency(line.averagePrice))
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(width: 100, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 900)
                }
                .frame(maxWidth: .infinity)
            } else {
                emptyState(icon: "shippingbox", message: "No historical QuickBooks sales-by-item summary has been loaded yet.")
            }
        }
        .onAppear {
            if report == nil {
                loadReport()
            }
        }
    }

    private func loadReport() {
        report = try? model.db.fetchHistoricalSalesByItemReport()
    }
}

// MARK: - AR Aging

struct ARAgingReportView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var rows: [ARAgingRow] = []
    @State private var asOfDate = Date()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("As of:").foregroundStyle(AppTheme.ink3)
                SmartDateField(date: $asOfDate)
                Button("Run Report") { runReport() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            Divider()

            if !hasRun {
                emptyState(icon: "calendar.badge.clock", message: "Click Run Report to see outstanding receivables.")
            } else if rows.isEmpty {
                emptyState(icon: "checkmark.circle", message: "No outstanding receivables as of this date.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Column headers
                        HStack(spacing: 0) {
                            Text("Customer").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Current").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("1-30 Days").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("31-60 Days").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("61-90 Days").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("Over 90").font(.caption.bold()).foregroundStyle(AppTheme.bad)
                                .frame(width: 100, alignment: .trailing)
                            Text("Total").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.surface)

                        Divider()

                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.displayCustomerName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                amtCell(row.current, color: .primary)
                                amtCell(row.days1_30, color: .primary)
                                amtCell(row.days31_60, color: AppTheme.warn)
                                amtCell(row.days61_90, color: AppTheme.warn)
                                amtCell(row.over90, color: AppTheme.bad)
                                Text(rptCurrency(row.total))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            Divider()
                        }

                        // Totals row
                        let totals = agingTotals
                        HStack(spacing: 0) {
                            Text("TOTAL").font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            amtCell(totals.current, color: .primary, bold: true)
                            amtCell(totals.d1_30, color: .primary, bold: true)
                            amtCell(totals.d31_60, color: .orange, bold: true)
                            amtCell(totals.d61_90, color: .orange, bold: true)
                            amtCell(totals.over90, color: .red, bold: true)
                            Text(rptCurrency(totals.total))
                                .font(.subheadline.bold())
                                .fontDesign(.monospaced)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.surface)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var agingTotals: (current: Double, d1_30: Double, d31_60: Double, d61_90: Double, over90: Double, total: Double) {
        (
            current: rows.reduce(0) { $0 + $1.current },
            d1_30: rows.reduce(0) { $0 + $1.days1_30 },
            d31_60: rows.reduce(0) { $0 + $1.days31_60 },
            d61_90: rows.reduce(0) { $0 + $1.days61_90 },
            over90: rows.reduce(0) { $0 + $1.over90 },
            total: rows.reduce(0) { $0 + $1.total }
        )
    }

    private func amtCell(_ amount: Double, color: Color, bold: Bool = false) -> some View {
        let text = amount > 0.01 ? rptCurrency(amount) : "—"
        return Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(amount > 0.01 ? color : .secondary)
            .frame(width: 100, alignment: .trailing)
    }

    private func runReport() {
        let fmt = DateFormatter.isoDate
        rows = (try? model.db.fetchARAgingReport(asOf: fmt.string(from: asOfDate))) ?? []
        hasRun = true
    }
}

// MARK: - A/P Aging

/// Payables aging: what Dad owes vendors, bucketed by how overdue each unpaid
/// bill is. The payable mirror of `ARAgingReportView`.
struct APAgingReportView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var rows: [APAgingRow] = []
    @State private var asOfDate = Date()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("As of:").foregroundStyle(AppTheme.ink3)
                SmartDateField(date: $asOfDate)
                Button("Run Report") { runReport() }
                    .buttonStyle(.renaissancePrimary)
                Spacer()
                Button {
                    PDFExportService.printView(
                        jobTitle: "A-P Aging \(DateFormatter.isoDate.string(from: asOfDate))",
                        view: APAgingPrintView(rows: rows, asOf: DateFormatter.isoDate.string(from: asOfDate), companyInfo: model.companyInfo)
                    )
                } label: {
                    Label("Print / PDF", systemImage: "printer")
                }
                .buttonStyle(.renaissanceSecondary)
                .disabled(!hasRun || rows.isEmpty)
            }
            .padding()

            Divider()

            if !hasRun {
                emptyState(icon: "calendar.badge.clock", message: "Click Run Report to see unpaid bills you owe.")
            } else if rows.isEmpty {
                emptyState(icon: "checkmark.circle", message: "No unpaid bills as of this date.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("Vendor").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Current").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("1-30 Days").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("31-60 Days").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("61-90 Days").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("Over 90").font(.caption.bold()).foregroundStyle(AppTheme.bad)
                                .frame(width: 100, alignment: .trailing)
                            Text("Total").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.surface)

                        Divider()

                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.displayVendorName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                amtCell(row.current, color: .primary)
                                amtCell(row.days1_30, color: .primary)
                                amtCell(row.days31_60, color: AppTheme.warn)
                                amtCell(row.days61_90, color: AppTheme.warn)
                                amtCell(row.over90, color: AppTheme.bad)
                                Text(rptCurrency(row.total))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            Divider()
                        }

                        let totals = agingTotals
                        HStack(spacing: 0) {
                            Text("TOTAL").font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            amtCell(totals.current, color: .primary, bold: true)
                            amtCell(totals.d1_30, color: .primary, bold: true)
                            amtCell(totals.d31_60, color: .orange, bold: true)
                            amtCell(totals.d61_90, color: .orange, bold: true)
                            amtCell(totals.over90, color: .red, bold: true)
                            Text(rptCurrency(totals.total))
                                .font(.subheadline.bold())
                                .fontDesign(.monospaced)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.surface)
                    }
                    .padding(16)
                }
            }
        }
        .accessibilityIdentifier("reports.apAging")
    }

    private var agingTotals: (current: Double, d1_30: Double, d31_60: Double, d61_90: Double, over90: Double, total: Double) {
        (
            current: rows.reduce(0) { $0 + $1.current },
            d1_30: rows.reduce(0) { $0 + $1.days1_30 },
            d31_60: rows.reduce(0) { $0 + $1.days31_60 },
            d61_90: rows.reduce(0) { $0 + $1.days61_90 },
            over90: rows.reduce(0) { $0 + $1.over90 },
            total: rows.reduce(0) { $0 + $1.total }
        )
    }

    private func amtCell(_ amount: Double, color: Color, bold: Bool = false) -> some View {
        let text = amount > 0.01 ? rptCurrency(amount) : "—"
        return Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(amount > 0.01 ? color : .secondary)
            .frame(width: 100, alignment: .trailing)
    }

    private func runReport() {
        let fmt = DateFormatter.isoDate
        rows = (try? model.db.fetchAPAgingReport(asOf: fmt.string(from: asOfDate))) ?? []
        hasRun = true
    }
}

/// Print/PDF layout for the A/P aging report (white page, black text).
struct APAgingPrintView: View {
    let rows: [APAgingRow]
    let asOf: String
    var companyInfo: CompanyInfo = CompanyInfo()

    private var totals: (current: Double, d1_30: Double, d31_60: Double, d61_90: Double, over90: Double, total: Double) {
        (
            rows.reduce(0) { $0 + $1.current },
            rows.reduce(0) { $0 + $1.days1_30 },
            rows.reduce(0) { $0 + $1.days31_60 },
            rows.reduce(0) { $0 + $1.days61_90 },
            rows.reduce(0) { $0 + $1.over90 },
            rows.reduce(0) { $0 + $1.total }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companyInfo.name).font(.system(size: 20, weight: .bold))
                    Text("A/P Aging Summary").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack { Text("As of").foregroundStyle(.secondary); Text(asOf).bold() }
                }
            }
            .padding(.bottom, 20)

            Divider()

            HStack(spacing: 0) {
                Text("Vendor").font(.system(size: 9, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Current").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .trailing)
                Text("1-30").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .trailing)
                Text("31-60").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .trailing)
                Text("61-90").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .trailing)
                Text("Over 90").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .trailing)
                Text("Total").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 5).padding(.horizontal, 4)
            .background(Color.gray.opacity(0.12))

            ForEach(rows) { row in
                HStack(spacing: 0) {
                    Text(row.displayVendorName).frame(maxWidth: .infinity, alignment: .leading)
                    apCell(row.current); apCell(row.days1_30); apCell(row.days31_60)
                    apCell(row.days61_90); apCell(row.over90)
                    Text(rptCurrency(row.total)).font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 4).padding(.vertical, 3)
                Divider()
            }

            HStack(spacing: 0) {
                Text("TOTAL").font(.system(size: 10, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                apCell(totals.current, bold: true); apCell(totals.d1_30, bold: true); apCell(totals.d31_60, bold: true)
                apCell(totals.d61_90, bold: true); apCell(totals.over90, bold: true)
                Text(rptCurrency(totals.total)).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 4).padding(.vertical, 5)
            .background(Color.gray.opacity(0.12))

            Spacer()
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .font(.system(size: 11))
        .environment(\.colorScheme, .light)
    }

    private func apCell(_ amount: Double, bold: Bool = false) -> some View {
        Text(amount > 0.01 ? rptCurrency(amount) : "—")
            .font(.system(size: 9, weight: bold ? .bold : .regular, design: .monospaced))
            .frame(width: 70, alignment: .trailing)
    }
}

// MARK: - Bank Reconciliation Report

/// Read-only history of completed (and any in-progress) bank reconciliations:
/// a "Previous Reconciliations" list per account plus the cleared-item detail
/// for the selected one. Mirrors the reconciliation report Dad keeps from QB.
struct ReconciliationReportView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var accounts: [ReconcileAccount] = []
    @State private var selectedAccountID: Int64 = 0
    @State private var reconciliations: [Reconciliation] = []
    @State private var selectedReconciliationID: Int64?
    @State private var items: [ReconcileItem] = []

    private var selectedReconciliation: Reconciliation? {
        reconciliations.first { $0.id == selectedReconciliationID }
    }

    private var tally: ReconcileTally? {
        guard let recon = selectedReconciliation else { return nil }
        return ReconcileTally(beginningBalance: recon.beginningBalance, endingBalance: recon.endingBalance, clearedItems: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Account:").foregroundStyle(AppTheme.ink3)
                Picker("", selection: $selectedAccountID) {
                    Text("- Select Account -").tag(Int64(0))
                    ForEach(accounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: selectedAccountID) { _ in loadReconciliations() }
                Spacer()
                Button("Refresh") { loadReconciliations() }
                    .buttonStyle(.renaissanceSecondary)
            }
            .padding()

            Divider()

            if accounts.isEmpty {
                emptyState(icon: "building.columns", message: "No bank accounts are available to reconcile yet.")
            } else if reconciliations.isEmpty {
                emptyState(icon: "checkmark.seal", message: "No reconciliations have been recorded for this account yet.")
            } else {
                HSplitView {
                    previousList
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    detail
                }
            }
        }
        .onAppear(perform: loadAccounts)
        .accessibilityIdentifier("reports.reconciliation")
    }

    private var previousList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Previous Reconciliations")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ink3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(reconciliations) { recon in
                        Button {
                            selectReconciliation(recon.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recon.statementDate)
                                        .font(.system(size: 13, design: .monospaced))
                                    Text(recon.isReconciled ? "Reconciled" : "In progress")
                                        .font(.caption)
                                        .foregroundStyle(recon.isReconciled ? AppTheme.ok : AppTheme.warn)
                                }
                                Spacer()
                                Text(rptCurrency(recon.endingBalance))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppTheme.ink3)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(recon.id == selectedReconciliationID ? AppTheme.panel : Color.clear)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private var detail: some View {
        Group {
            if let recon = selectedReconciliation, let tally {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reconciliation — \(recon.accountName)")
                                    .font(.title3.bold())
                                Text("Statement ending \(recon.statementDate)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                            Spacer()
                            Button {
                                PDFExportService.printView(
                                    jobTitle: "Reconciliation \(recon.accountName) \(recon.statementDate)",
                                    view: ReconciliationPrintView(reconciliation: recon, items: items, companyInfo: model.companyInfo)
                                )
                            } label: {
                                Label("Print / PDF", systemImage: "printer")
                            }
                            .buttonStyle(.renaissanceSecondary)
                        }

                        VStack(spacing: 0) {
                            summaryRow("Beginning Balance", recon.beginningBalance)
                            Divider()
                            summaryRow("Cleared Deposits (+)", tally.clearedDeposits, color: AppTheme.ok)
                            Divider()
                            summaryRow("Cleared Payments (−)", tally.clearedPayments, color: AppTheme.bad)
                            Divider()
                            summaryRow("Cleared Balance", tally.clearedBalance)
                            Divider()
                            summaryRow("Statement Ending Balance", recon.endingBalance)
                            Divider()
                            summaryRow("Difference", tally.difference, color: tally.isBalanced ? AppTheme.ok : AppTheme.bad, bold: true)
                        }
                        .background(AppTheme.panel)
                        .cornerRadius(8)

                        Text("Cleared Items (\(items.count))")
                            .font(.headline)

                        clearedItemsTable
                    }
                    .padding(20)
                }
            } else {
                emptyState(icon: "doc.text.magnifyingglass", message: "Select a reconciliation to view its report.")
            }
        }
    }

    private var clearedItemsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Date").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Payee / Source").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Ref").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 90, alignment: .leading)
                Text("Payment").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
                Text("Deposit").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.surface)
            Divider()
            ForEach(items) { item in
                HStack(spacing: 0) {
                    Text(item.date)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 100, alignment: .leading)
                    Text(item.displayPayee.isEmpty ? sourceLabel(item) : item.displayPayee)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.reference.isEmpty ? "-" : item.reference)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.ink3)
                        .frame(width: 90, alignment: .leading)
                    Text(item.isDeposit ? "" : rptCurrency(item.paymentAmount))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.bad)
                        .frame(width: 110, alignment: .trailing)
                    Text(item.isDeposit ? rptCurrency(item.depositAmount) : "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.ok)
                        .frame(width: 110, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                Divider()
            }
        }
        .background(AppTheme.panel)
        .cornerRadius(8)
    }

    private func summaryRow(_ label: String, _ amount: Double, color: Color = .primary, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.bold() : .subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(rptCurrency(amount))
                .font(.system(size: 13, weight: bold ? .bold : .regular, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        accounts = (try? model.db.fetchReconcilableAccounts()) ?? []
        if selectedAccountID == 0 { selectedAccountID = accounts.first?.id ?? 0 }
        loadReconciliations()
    }

    private func loadReconciliations() {
        guard selectedAccountID != 0 else { reconciliations = []; items = []; selectedReconciliationID = nil; return }
        reconciliations = (try? model.db.fetchReconciliations(accountID: selectedAccountID)) ?? []
        if let first = reconciliations.first {
            selectReconciliation(first.id)
        } else {
            selectedReconciliationID = nil
            items = []
        }
    }

    private func selectReconciliation(_ id: Int64) {
        selectedReconciliationID = id
        items = (try? model.db.fetchReconciledItems(reconciliationID: id)) ?? []
    }
}

/// Print/PDF layout for a completed reconciliation — the record Dad keeps,
/// styled like the other printable documents (white page, black text).
struct ReconciliationPrintView: View {
    let reconciliation: Reconciliation
    let items: [ReconcileItem]
    var companyInfo: CompanyInfo = CompanyInfo()

    private var clearedDeposits: Double { items.reduce(0) { $0 + $1.depositAmount } }
    private var clearedPayments: Double { items.reduce(0) { $0 + $1.paymentAmount } }
    private var clearedBalance: Double { reconciliation.beginningBalance + clearedDeposits - clearedPayments }
    private var difference: Double { reconciliation.endingBalance - clearedBalance }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companyInfo.name).font(.system(size: 20, weight: .bold))
                    Text("Bank Reconciliation Report")
                        .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack { Text("Account").foregroundStyle(.secondary); Text(reconciliation.accountName).bold() }
                    HStack { Text("Statement Date").foregroundStyle(.secondary); Text(reconciliation.statementDate) }
                    HStack { Text("Status").foregroundStyle(.secondary); Text(reconciliation.status.capitalized) }
                }
            }
            .padding(.bottom, 20)

            Divider()

            VStack(spacing: 6) {
                summaryLine("Beginning Balance", reconciliation.beginningBalance)
                summaryLine("Cleared Deposits (+)", clearedDeposits)
                summaryLine("Cleared Payments (−)", clearedPayments)
                summaryLine("Cleared Balance", clearedBalance)
                summaryLine("Statement Ending Balance", reconciliation.endingBalance)
                summaryLine("Difference", difference, bold: true)
            }
            .padding(.vertical, 14)

            Divider()

            Text("CLEARED ITEMS (\(items.count))")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 12).padding(.bottom, 4)

            HStack(spacing: 0) {
                Text("Date").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .leading)
                Text("Payee / Source").font(.system(size: 9, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Ref").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .leading)
                Text("Payment").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .trailing)
                Text("Deposit").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 5).padding(.horizontal, 4)
            .background(Color.gray.opacity(0.12))

            ForEach(items) { item in
                HStack(spacing: 0) {
                    Text(item.date).font(.system(size: 9, design: .monospaced)).frame(width: 80, alignment: .leading)
                    Text(item.displayPayee.isEmpty ? item.sourceKind.rawValue.capitalized : item.displayPayee)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.reference.isEmpty ? "-" : item.reference)
                        .font(.system(size: 9, design: .monospaced)).frame(width: 70, alignment: .leading)
                    Text(item.isDeposit ? "" : rptCurrency(item.paymentAmount))
                        .font(.system(size: 9, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Text(item.isDeposit ? rptCurrency(item.depositAmount) : "")
                        .font(.system(size: 9, design: .monospaced)).frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 4).padding(.vertical, 3)
                Divider()
            }

            Spacer()

            Divider()
            Text("Reconciled \(reconciliation.reconciledAt.isEmpty ? reconciliation.statementDate : reconciliation.reconciledAt)")
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 6)
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .font(.system(size: 11))
        .environment(\.colorScheme, .light)
    }

    private func summaryLine(_ label: String, _ amount: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: bold ? .bold : .regular))
            Spacer()
            Text(rptCurrency(amount))
                .font(.system(size: 11, weight: bold ? .bold : .regular, design: .monospaced))
        }
    }
}

// MARK: - 1099

struct Report1099View: View {
    @EnvironmentObject private var model: AppViewModel
    let initialYear: Int?
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var rows: [Report1099Row] = []
    @State private var hasRun = false
    @State private var includeLiveExpenseReview = false

    private var canOfferLiveExpenseReview: Bool { true }

    private var usesHistoricalSnapshot: Bool {
        rows.first?.source == .historicalSnapshot
    }

    private var filingRows: [Report1099Row] {
        rows.filter { !reviewContext(for: $0).isInternalSelf }
    }

    private var internalRows: [Report1099Row] {
        rows.filter { reviewContext(for: $0).isInternalSelf }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Year:").foregroundStyle(AppTheme.ink3)
                Picker("Year", selection: $year) {
                    ForEach((2018...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .frame(width: 100)
                .labelsHidden()
                if canOfferLiveExpenseReview {
                    Toggle("Include live payee review", isOn: $includeLiveExpenseReview)
                        .toggleStyle(.checkbox)
                }
                Button("Run Report") { runReport() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            Divider()

            if !hasRun {
                emptyState(icon: "doc.text", message: "Click Run Report to see historical QuickBooks 1099 totals. Live 1099 review stays off unless you explicitly enable it.")
            } else if rows.isEmpty {
                if canOfferLiveExpenseReview && !includeLiveExpenseReview {
                    VStack(spacing: 16) {
                        emptyState(icon: "checkmark.circle", message: "No imported QuickBooks 1099 snapshot is available for \(year).\n\nLive 1099 review is currently off by default.")
                        Button("Review Flagged Payees for \(year)") {
                            includeLiveExpenseReview = true
                            runReport()
                        }
                        .buttonStyle(.renaissancePrimary)
                    }
                } else {
                    emptyState(icon: "checkmark.circle", message: "No 1099 totals available for \(year).\n\nUse Payee Spend to inspect historical payee activity or enable live payee review for an explicit review pass.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1099 Summary - \(year)").font(.title2.bold())
                            Text(usesHistoricalSnapshot
                                 ? "Historical QuickBooks 1099 totals are being shown exactly as imported."
                                 : "No historical QuickBooks 1099 snapshot exists for \(year), so this screen is reviewing live payees with activity in \(year). Internal/self payees are excluded from the filing count below.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink3)
                        }

                        if !usesHistoricalSnapshot {
                            reportCallout(
                                title: "Live 1099 review is based on current payee flags and activity.",
                                message: "Use this as a review tool, not a filing-ready historical snapshot. If an internal/self payee is marked as a 1099 vendor, it will be shown separately for review instead of being counted as a filing candidate."
                            )
                        }

                        HStack(spacing: 0) {
                            Text("Vendor").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("EIN").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 130, alignment: .leading)
                            Text("Total Paid").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 120, alignment: .trailing)
                            Text("1099 Required?").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 130, alignment: .center)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface)

                        Divider()

                        ForEach(filingRows) { row in
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.displayVendorName)
                                    if let detail = row.displayVendorDetail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.ein.isEmpty ? "-" : row.ein)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(row.ein.isEmpty ? AppTheme.bad : .primary)
                                    .frame(width: 130, alignment: .leading)
                                Text(rptCurrency(row.totalPaid))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 120, alignment: .trailing)
                                HStack {
                                    if row.needs1099 {
                                        Label("YES", systemImage: "exclamationmark.circle.fill")
                                            .foregroundStyle(AppTheme.warn)
                                            .font(.caption.bold())
                                    } else {
                                        Label("No", systemImage: "checkmark.circle")
                                            .foregroundStyle(AppTheme.ink3)
                                            .font(.caption)
                                    }
                                }
                                .frame(width: 130, alignment: .center)
                            }
                            .foregroundStyle(AppTheme.bodyText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.canvas)
                            )
                            Divider()
                        }

                        if !internalRows.isEmpty {
                            reportCallout(
                                title: "\(internalRows.count) internal/self payee(s) were excluded from the 1099 filing count.",
                                message: "These payees match the company phone or a known internal/self payee alias. Their transactions remain visible in Payee Spend, but they are not counted here as filing candidates."
                            )

                            HStack(spacing: 0) {
                                Text("Internal / Self Payee").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Reason").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                    .frame(width: 250, alignment: .leading)
                                Text("Total Paid").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                    .frame(width: 120, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(AppTheme.surface)

                            Divider()

                            ForEach(internalRows) { row in
                                let context = reviewContext(for: row)
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.displayVendorName)
                                        if let detail = row.displayVendorDetail {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.ink3)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(context.shortReason)
                                        .frame(width: 250, alignment: .leading)
                                        .foregroundStyle(AppTheme.ink3)
                                    Text(rptCurrency(row.totalPaid))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .frame(width: 120, alignment: .trailing)
                                }
                                .foregroundStyle(AppTheme.bodyText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.orange.opacity(0.08))
                                )
                                Divider()
                            }
                        }

                        HStack {
                            Text("\(filingRows.filter { $0.needs1099 }.count) vendor(s) require a 1099-NEC for \(year).")
                                .font(.subheadline)
                                .foregroundStyle(filingRows.allSatisfy { !$0.needs1099 } ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    }
                    .padding(16)
                    .foregroundStyle(AppTheme.bodyText)
                }
                .background(AppTheme.surface)
            }
        }
        .background(AppTheme.surface)
        .onAppear {
            if let initialYear {
                year = initialYear
            }
            if !hasRun {
                runReport()
            }
        }
        .onChange(of: year) { _ in
            includeLiveExpenseReview = false
        }
    }

    private func runReport() {
        rows = (try? model.db.fetch1099Report(year: year, includeLiveExpenseReview: includeLiveExpenseReview)) ?? []
        hasRun = true
    }

    private func reviewContext(for row: Report1099Row) -> PayeeReviewContext {
        payeeReviewContext(for: row.vendorName, vendors: model.vendors, companyInfo: model.companyInfo)
    }

    private func reportCallout(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.warn)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Vendor Spend

struct VendorExpenseHistoryView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var selectedVendorID: Int64 = 0
    @State private var searchText = ""
    @State private var selectedYear = 0
    @State private var rows: [ExpenseRow] = []
    @State private var summary = VendorExpenseHistorySummary(
        searchText: "",
        year: nil,
        totalPaid: 0,
        transactionCount: 0,
        matchedVendorCount: 0,
        historical1099Total: nil
    )
    @State private var hasRun = false

    private var vendorOptions: [AutocompleteOption] {
        model.vendors.map {
            let subtitle = [$0.displayDetail, $0.company]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " - ")
            return AutocompleteOption(
                id: $0.id,
                title: $0.displayName,
                subtitle: subtitle,
                completionText: $0.displayName
            )
        }
    }

    private var selectedYearValue: Int? {
        selectedYear == 0 ? nil : selectedYear
    }

    private var yearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return [0] + Array((2015 ... currentYear).reversed())
    }

    private var searchedPayeeContext: PayeeReviewContext? {
        let trimmed = summary.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return payeeReviewContext(for: trimmed, vendors: model.vendors, companyInfo: model.companyInfo)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vendor / Payee")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    AutocompleteSelectionField(
                        placeholder: "Type a vendor or payee",
                        text: $searchText,
                        selectedID: $selectedVendorID,
                        options: vendorOptions,
                        allowsCustomValue: true,
                        accessibilityID: "reports.vendorHistory.searchField"
                    )
                    .frame(width: 280)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Year")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    Picker("Year", selection: $selectedYear) {
                        Text("All Years").tag(0)
                        ForEach(yearOptions.dropFirst(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .frame(width: 120)
                    .labelsHidden()
                }

                Button("Run Report") { runReport() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            if !hasRun {
                emptyState(icon: "person.2.badge.gearshape", message: "Type a vendor or payee and click Run Report.")
            } else if rows.isEmpty {
                emptyState(icon: "tray", message: "No expense history matched \"\(searchText)\".")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Payee Spend History").font(.title2.bold())
                            Text(summary.searchText)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink3)
                            Text(summary.year == nil ? "All Years" : "Year \(summary.year!)")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink3)
                            Text("This report searches recorded expense payees, including vendors, cards, banks, utilities, meals, and self-issued checks.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink3)
                        }

                        HStack(spacing: 14) {
                            vendorMetric("Transactions", value: "\(summary.transactionCount)")
                            vendorMetric("Total Paid", value: rptCurrency(summary.totalPaid))
                            vendorMetric("Matched Vendors", value: "\(summary.matchedVendorCount)")
                        }

                        if let context = searchedPayeeContext, context.isInternalSelf {
                            vendorHistoryCallout(
                                title: "This payee looks like an internal/self payee.",
                                message: context.longReason + " The transactions below are still part of the historical books, but they should be reviewed as pass-through or self-issued checks rather than assumed third-party vendor spending."
                            )
                        }

                        if let historical1099Total = summary.historical1099Total {
                            vendorHistoryCallout(
                                title: "Historical QB 1099 snapshot also matches this search.",
                                message: "Historical QB 1099 total: \(rptCurrency(historical1099Total)). Compare that to the visible expense history total before treating it as a clean year-specific 1099 amount."
                            )
                        }

                        HStack(spacing: 0) {
                            Text("Date").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .leading)
                            Text("Payee").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 180, alignment: .leading)
                            Text("Category").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 170, alignment: .leading)
                            Text("Paid From").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 150, alignment: .leading)
                            Text("Check #").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 90, alignment: .leading)
                            Text("Memo").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Amount").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface)

                        Divider()

                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.expenseDate)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 100, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.displayVendorName)
                                    if let detail = row.displayVendorDetail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                }
                                .frame(width: 180, alignment: .leading)
                                Text(row.accountName)
                                    .frame(width: 170, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(row.paymentAccountName)
                                    .frame(width: 150, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(row.checkNumber)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(row.displayMemo)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                    .lineLimit(1)
                                Text(rptCurrency(row.amount))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(AppTheme.surface)
    }

    private func runReport() {
        let rawSearch = model.vendors.first(where: { $0.id == selectedVendorID })?.name
            ?? searchText
        let displaySearch = model.vendors.first(where: { $0.id == selectedVendorID })?.displayName
            ?? searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        rows = (try? model.db.fetchVendorExpenseHistory(search: rawSearch, year: selectedYearValue)) ?? []
        let loadedSummary = (try? model.db.fetchVendorExpenseHistorySummary(search: rawSearch, year: selectedYearValue))
            ?? VendorExpenseHistorySummary(
                searchText: rawSearch,
                year: selectedYearValue,
                totalPaid: 0,
                transactionCount: 0,
                matchedVendorCount: 0,
                historical1099Total: nil
            )
        summary = VendorExpenseHistorySummary(
            searchText: displaySearch,
            year: loadedSummary.year,
            totalPaid: loadedSummary.totalPaid,
            transactionCount: loadedSummary.transactionCount,
            matchedVendorCount: loadedSummary.matchedVendorCount,
            historical1099Total: loadedSummary.historical1099Total
        )
        hasRun = true
    }

    private func vendorMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.canvas)
        )
    }

    private func vendorHistoryCallout(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.warn)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Job Profitability

struct JobProfitabilityReportView: View {
    @EnvironmentObject private var model: AppViewModel
    let initialCustomerID: Int64?
    @State private var selectedCustomerID: Int64 = 0
    @State private var includeInactive = false
    @State private var rows: [JobProfitabilityRow] = []
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Customer", selection: $selectedCustomerID) {
                    Text("All Customers").tag(Int64(0))
                    ForEach(model.customers) { customer in
                        Text(customer.displayLabel + (customer.company.isEmpty ? "" : " - " + customer.company)).tag(customer.id)
                    }
                }
                .frame(width: 280)
                Toggle("Include Inactive Jobs", isOn: $includeInactive)
                Button("Run Report") { runReport() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            Divider()

            if !hasRun {
                emptyState(icon: "briefcase", message: "Choose a customer if you want, then click Run Report.")
            } else if rows.isEmpty {
                emptyState(icon: "tray", message: "No jobs matched the current filters.")
            } else {
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            reportHeader("Customer", width: 180)
                            reportHeader("Job", width: 220)
                            reportHeader("Status", width: 100)
                            reportHeader("Estimates", width: 120)
                            reportHeader("Invoiced", width: 120)
                            reportHeader("Open Bal.", width: 120)
                            reportHeader("Expenses", width: 120)
                            reportHeader("Profit", width: 120)
                            reportHeader("Est. vs Actual", width: 140)
                            Spacer(minLength: 0)
                        }

                        Divider()

                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.displayCustomerName)
                                    .frame(width: 180, alignment: .leading)
                                Text(row.jobName)
                                    .frame(width: 220, alignment: .leading)
                                Text(row.status.capitalized)
                                    .foregroundStyle(row.isActive ? .primary : .secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(rptCurrency(row.estimateTotal))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 120, alignment: .trailing)
                                Text(rptCurrency(row.invoicedTotal))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 120, alignment: .trailing)
                                Text(rptCurrency(row.openInvoiceBalance))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(row.openInvoiceBalance > 0.01 ? AppTheme.warn : .secondary)
                                    .frame(width: 120, alignment: .trailing)
                                Text(rptCurrency(row.expenseTotal))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppTheme.bad)
                                    .frame(width: 120, alignment: .trailing)
                                Text(rptCurrency(row.profit))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(row.profit >= 0 ? AppTheme.ok : AppTheme.bad)
                                    .frame(width: 120, alignment: .trailing)
                                Text(rptCurrency(row.estimateVsActualDelta))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(row.estimateVsActualDelta >= 0 ? AppTheme.ok : AppTheme.warn)
                                    .frame(width: 140, alignment: .trailing)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            if let initialCustomerID, selectedCustomerID == 0 {
                selectedCustomerID = initialCustomerID
            }
        }
    }

    private func runReport() {
        rows = (try? model.db.fetchJobProfitability(
            customerID: selectedCustomerID == 0 ? nil : selectedCustomerID,
            includeInactive: includeInactive
        )) ?? []
        hasRun = true
    }

    private func reportHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(AppTheme.ink3)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.surface)
    }
}

// MARK: - Customer Statement

struct CustomerStatementView: View {
    @EnvironmentObject private var model: AppViewModel
    let initialCustomerID: Int64?
    @State private var selectedCustomerID: Int64 = 0
    @State private var lines: [CustomerStatementLine] = []
    @State private var hasRun = false

    private var selectedCustomer: CustomerRow? {
        model.customers.first { $0.id == selectedCustomerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Customer", selection: $selectedCustomerID) {
                    Text("- Select Customer -").tag(Int64(0))
                    ForEach(model.customers) { c in
                        Text(c.displayLabel + (c.company.isEmpty ? "" : " - " + c.company)).tag(c.id)
                    }
                }
                .frame(width: 260)
                Button("Run Report") { runReport() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(selectedCustomerID == 0)
                if hasRun && !lines.isEmpty {
                    Button("Print Statement") { printStatement() }
                }
            }
            .padding()

            Divider()

            statementContent
        }
        .onAppear {
            if selectedCustomerID == 0, let initialCustomerID {
                selectedCustomerID = initialCustomerID
                runReport()
            }
        }
    }

    @ViewBuilder private var statementContent: some View {
        if !hasRun || selectedCustomerID == 0 {
            emptyState(icon: "person.text.rectangle", message: "Select a customer and click Run Report.")
        } else if lines.isEmpty {
            emptyState(icon: "tray", message: "No transactions for this customer.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let c = selectedCustomer {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Statement").font(.title2.bold())
                            Text(c.displayLabel + (c.company.isEmpty ? "" : " - " + c.company))
                                .font(.headline).foregroundStyle(AppTheme.ink3)
                        }
                        .padding(.bottom, 16)
                    }

                    statementHeader
                    Divider()
                    statementRows
                    statementBalance
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder private var statementHeader: some View {
        HStack(spacing: 0) {
            Text("Date").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                .frame(width: 100, alignment: .leading)
            Text("Type").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                .frame(width: 110, alignment: .leading)
            Text("Reference").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Amount").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                .frame(width: 120, alignment: .trailing)
            Text("Balance").font(.caption.bold()).foregroundStyle(AppTheme.ink3)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
    }

    @ViewBuilder private var statementRows: some View {
        ForEach(lines) { line in
            statementRow(line)
            Divider()
        }
    }

    private func statementRow(_ line: CustomerStatementLine) -> some View {
        HStack(spacing: 0) {
            Text(line.date)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 100, alignment: .leading)
            Text(line.type)
                .font(.caption)
                .foregroundStyle(statementTypeTint(line))
                .frame(width: 110, alignment: .leading)
            Text(line.reference)
                .foregroundStyle(AppTheme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(statementAmountLabel(line))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(statementAmountTint(line))
                .frame(width: 120, alignment: .trailing)
            Text(rptCurrency(line.balance))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(line.balance > 0.01 ? AnyShapeStyle(AppTheme.bad) : AnyShapeStyle(AppTheme.ok))
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statementBalance: some View {
        if let last = lines.last {
            HStack {
                Text("Current Balance").font(.headline)
                Spacer()
                Text(rptCurrency(last.balance))
                    .font(.title3.bold())
                    .foregroundStyle(last.balance > 0.01 ? AnyShapeStyle(AppTheme.bad) : AnyShapeStyle(AppTheme.ok))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
        }
    }

    private func runReport() {
        lines = (try? model.db.fetchCustomerStatement(customerID: selectedCustomerID)) ?? []
        hasRun = true
    }

    private func printStatement() {
        guard let customer = selectedCustomer else { return }
        let view = StatementPrintView(customer: customer, lines: lines, companyInfo: model.companyInfo)
        let hostView = NSHostingView(rootView: view)
        hostView.frame = CGRect(x: 0, y: 0, width: 612, height: 792)
        let op = NSPrintOperation(view: hostView)
        op.printInfo.horizontalPagination = .fit
        op.printInfo.verticalPagination = .automatic
        op.run()
    }

    private func statementTypeTint(_ line: CustomerStatementLine) -> AnyShapeStyle {
        if line.type == "Estimate" {
            return AnyShapeStyle(.secondary)
        }
        return line.amount < 0 ? AnyShapeStyle(AppTheme.ok) : AnyShapeStyle(.blue)
    }

    private func statementAmountLabel(_ line: CustomerStatementLine) -> String {
        if line.type == "Estimate" {
            return "-"
        }
        if line.amount < 0 {
            return "(\(rptCurrency(-line.amount)))"
        }
        return rptCurrency(line.amount)
    }

    private func statementAmountTint(_ line: CustomerStatementLine) -> AnyShapeStyle {
        if line.type == "Estimate" {
            return AnyShapeStyle(.secondary)
        }
        return line.amount < 0 ? AnyShapeStyle(AppTheme.ok) : AnyShapeStyle(.primary)
    }
}

// MARK: - Statement Print View

private struct StatementPrintView: View {
    let customer: CustomerRow
    let lines: [CustomerStatementLine]
    var companyInfo: CompanyInfo = CompanyInfo()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companyInfo.name)
                        .font(.system(size: 18, weight: .bold))
                    if !companyInfo.address1.isEmpty {
                        Text(companyInfo.address1)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !companyInfo.cityStateZip.isEmpty {
                        Text(companyInfo.cityStateZip)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !companyInfo.phone.isEmpty {
                        Text(companyInfo.phone)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !companyInfo.licenseNumber.isEmpty {
                        Text("Lic# \(companyInfo.licenseNumber)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Text("Account Statement")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ink3)
                        .padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Customer:").foregroundColor(AppTheme.ink3) + Text(" \(customer.displayName)").bold()
                    if let detail = customer.displayDetail {
                        Text(detail).foregroundStyle(AppTheme.ink3)
                    }
                    if !customer.company.isEmpty {
                        Text(customer.company).foregroundStyle(AppTheme.ink3)
                    }
                    Text("Date: \(DateFormatter.isoDate.string(from: Date()))")
                        .foregroundStyle(AppTheme.ink3)
                }
            }
            .padding(.bottom, 20)

            Divider()

            HStack(spacing: 0) {
                Text("Date").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .leading)
                Text("Type").font(.system(size: 9, weight: .bold)).frame(width: 100, alignment: .leading)
                Text("Reference").font(.system(size: 9, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Amount").font(.system(size: 9, weight: .bold)).frame(width: 90, alignment: .trailing)
                Text("Balance").font(.system(size: 9, weight: .bold)).frame(width: 90, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .background(AppTheme.surface)

            ForEach(lines) { line in
                HStack(spacing: 0) {
                    Text(line.date).font(.system(size: 9, design: .monospaced)).frame(width: 80, alignment: .leading)
                    Text(line.type).font(.system(size: 9)).frame(width: 100, alignment: .leading)
                    Text(line.reference).font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(statementPrintAmountLabel(line))
                        .font(.system(size: 9, design: .monospaced)).frame(width: 90, alignment: .trailing)
                    Text(rptCurrency(line.balance))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 3)
                Divider()
            }

            if let last = lines.last {
                HStack {
                    Text("BALANCE DUE").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text(rptCurrency(last.balance))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(last.balance > 0.01 ? AppTheme.bad : AppTheme.ok)
                }
                .padding(.top, 12)
            }

            Spacer()
        }
        .padding(36)
    }
}

private func statementPrintAmountLabel(_ line: CustomerStatementLine) -> String {
    if line.type == "Estimate" {
        return "-"
    }
    if line.amount < 0 {
        return "(\(rptCurrency(-line.amount)))"
    }
    return rptCurrency(line.amount)
}

// MARK: - Shared helpers

private struct ReportSourceBadge: View {
    let kind: ReportSourceKind
    var compact = false

    var body: some View {
        Text(compact ? kind.shortTitle : kind.title)
            .font(.caption.bold())
            .foregroundStyle(kind.color)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                Capsule()
                    .fill(kind.color.opacity(0.14))
                    .overlay(Capsule().stroke(kind.color.opacity(0.35), lineWidth: 1))
            )
            .accessibilityLabel(kind.title)
    }
}

private struct ReportSection: View {
    let title: String
    let lines: [PLReportLine]
    let total: Double
    let totalLabel: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.bold()).foregroundStyle(AppTheme.ink3).padding(.bottom, 6)
            if lines.isEmpty {
                Text("No data for this period.").foregroundStyle(AppTheme.ink3).font(.subheadline).padding(.vertical, 4)
            } else {
                ForEach(lines) { line in
                    HStack {
                        Text(line.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(rptCurrency(line.total)).font(.system(.body, design: .monospaced))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    Divider()
                }
            }
            HStack {
                Text(totalLabel).font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Text(rptCurrency(total)).font(.subheadline.bold()).foregroundStyle(color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.surface)
            .cornerRadius(6)
        }
    }
}

private func emptyState(icon: String, message: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: icon).font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
        Text(message).foregroundStyle(AppTheme.ink3).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private func rptCurrency(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
