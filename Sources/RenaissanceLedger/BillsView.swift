import SwiftUI

struct BillsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showAddSheet = false
    @State private var showPayBillsSheet = false
    @State private var showRecordDepositSheet = false
    @State private var payBillsPreselectedIDs: Set<Int64> = []
    @State private var showUnpaidOnly = true
    @State private var search = ""

    private var filteredBills: [BillRow] {
        let source = showUnpaidOnly ? model.bills.filter { $0.status == "unpaid" } : model.bills
        guard !search.isEmpty else { return source }
        return source.filter {
            $0.displayVendorName.localizedCaseInsensitiveContains(search)
            || $0.vendorName.localizedCaseInsensitiveContains(search)
            || $0.displayJobName.localizedCaseInsensitiveContains(search)
            || $0.displayMemo.localizedCaseInsensitiveContains(search)
        }
    }

    private var totalUnpaid: Double {
        model.bills.filter { $0.status == "unpaid" }.reduce(0) { $0 + $1.amount }
    }

    // Vendor credits = bills with a negative amount (money vendors owe us / unused credits).
    private var vendorCreditsTotal: Double {
        model.bills.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        let visibleBills: [BillRow] = self.filteredBills
        VStack(spacing: 0) {
            HStack {
                Text("Bills / AP")
                    .font(.title2.bold())
                Spacer()
                Toggle("Unpaid Only", isOn: $showUnpaidOnly)
                    .toggleStyle(.checkbox)
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Record Deposit") { showRecordDepositSheet = true }
                Button("Pay Bills") {
                    payBillsPreselectedIDs = []
                    showPayBillsSheet = true
                }
                .disabled(model.bills.filter { $0.status == "unpaid" }.isEmpty)
                Button("+ Enter Bill") { showAddSheet = true }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()

            if totalUnpaid > 0 {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.warn)
                    Text("Total unpaid: \(billCurrency(totalUnpaid))")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.warn)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if vendorCreditsTotal < -0.005 {
                HStack {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text("Vendor credits on file: \(billCurrency(-vendorCreditsTotal)) (reduces what we owe)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            HStack(spacing: 0) {
                Text("Vendor").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Bill Date").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(width: 100, alignment: .leading)
                Text("Due Date").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(width: 100, alignment: .leading)
                Text("Category").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(width: 180, alignment: .leading)
                Text("Status").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(width: 70, alignment: .leading)
                Text("Amount").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if visibleBills.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Bills").font(.title2)
                    Text(showUnpaidOnly ? "No unpaid bills — all caught up!" : "No bills entered yet.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleBills.enumerated()), id: \.element.id) { _, bill in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bill.displayVendorName)
                                if let detail = bill.displayVendorDetail {
                                    Text(detail).font(.caption).foregroundStyle(AppTheme.ink3)
                                }
                                if bill.hasJob {
                                    Text("Job: \(bill.displayJobName)").font(.caption).foregroundStyle(AppTheme.accent)
                                }
                                if !bill.displayMemo.isEmpty {
                                    Text(bill.displayMemo).font(.caption).foregroundStyle(AppTheme.ink3)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(bill.billDate)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            Text(bill.dueDate)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                                .foregroundStyle(isOverdue(bill) ? AppTheme.bad : .primary)
                            Text(bill.accountName)
                                .foregroundStyle(AppTheme.ink3)
                                .frame(width: 180, alignment: .leading)
                            Text(bill.amount < 0 ? "Credit" : bill.status.capitalized)
                                .font(.caption.bold())
                                .foregroundStyle(bill.amount < 0 ? AppTheme.accent : (bill.status == "paid" ? AppTheme.ok : AppTheme.warn))
                                .frame(width: 70, alignment: .leading)
                            Text(bill.amount < 0 ? "\(billCurrency(-bill.amount)) CR" : billCurrency(bill.amount))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(bill.amount < 0 ? AppTheme.accent : .primary)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if bill.status == "unpaid" && bill.amount >= 0 {
                                Button("Pay") {
                                    payBillsPreselectedIDs = [bill.id]
                                    showPayBillsSheet = true
                                }
                                    .tint(AppTheme.ok)
                            }
                            Button("Delete", role: .destructive) { deleteBill(bill) }
                        }
                        Divider()
                    }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddBillSheet {
                showAddSheet = false
                model.refreshBills()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showRecordDepositSheet) {
            RecordDepositSheet {
                showRecordDepositSheet = false
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showPayBillsSheet) {
            PayBillsSheet(preselectedBillIDs: payBillsPreselectedIDs) {
                showPayBillsSheet = false
                model.refreshBills()
            }
            .environmentObject(model)
        }
    }

    private func deleteBill(_ bill: BillRow) {
        try? model.db.deleteBill(id: bill.id)
        model.refreshBills()
    }

    private func isOverdue(_ bill: BillRow) -> Bool {
        // Vendor credits (negative amounts) are never "overdue" — they're money in our favor.
        guard bill.status == "unpaid", bill.amount >= 0, !bill.dueDate.isEmpty else { return false }
        let today = DateFormatter.isoDate.string(from: Date())
        return bill.dueDate < today
    }
}

struct AddBillSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var onSave: () -> Void

    @State private var selectedVendorID: Int64 = 0
    @State private var vendorName = ""
    @State private var billDate = Date()
    @State private var dueDate = Date().addingTimeInterval(30 * 86400)
    @State private var amount = ""
    @State private var selectedAccountID: Int64 = 0
    @State private var selectedCustomerID: Int64 = 0
    @State private var selectedJobID: Int64 = 0
    @State private var memo = ""
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    private var expenseAccounts: [AccountRow] { model.accounts.filter { $0.type == "expense" } }
    private var activeJobsForCustomer: [JobRow] {
        guard selectedCustomerID != 0 else { return [] }
        return model.jobs.filter { $0.customerID == selectedCustomerID && $0.isActive }
    }
    private var vendorOptions: [AutocompleteOption] {
        model.vendors.map {
            AutocompleteOption(
                id: $0.id,
                title: $0.displayLabel,
                subtitle: $0.company,
                completionText: $0.displayName
            )
        }
    }
    private var categoryOptions: [AutocompleteOption] {
        expenseAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }
    @State private var categoryNameText = ""
    private var trimmedAmount: String {
        amount.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    private var canSave: Bool {
        !vendorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(trimmedAmount) ?? 0) > 0 &&
        selectedAccountID != 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Enter Bill")
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                Section("Vendor") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vendor / Payee *").font(.caption).foregroundStyle(AppTheme.ink3)
                        AutocompleteSelectionField(
                            placeholder: "Type or pick a vendor",
                            text: $vendorName,
                            selectedID: $selectedVendorID,
                            options: vendorOptions,
                            allowsCustomValue: true,
                            accessibilityID: "bill.vendorField"
                        )
                    }
                }
                Section("Bill Details") {
                    LabeledContent("Bill Date") { SmartDateField(date: $billDate) }
                    LabeledContent("Due Date") { SmartDateField(date: $dueDate) }
                    HStack {
                        Text("Amount *")
                        Spacer()
                        CalcStringField(text: $amount, placeholder: "0.00")
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category *").font(.caption).foregroundStyle(AppTheme.ink3)
                        AutocompleteSelectionField(
                            placeholder: "Pick an expense category",
                            text: $categoryNameText,
                            selectedID: $selectedAccountID,
                            options: categoryOptions,
                            accessibilityID: "bill.categoryField"
                        )
                    }
                    TextField("Memo", text: $memo)
                }
                Section("Job Costing (optional)") {
                    Picker("Customer", selection: $selectedCustomerID) {
                        Text("No customer/job").tag(Int64(0))
                        ForEach(model.customers) { customer in
                            Text(customer.displayName).tag(customer.id)
                        }
                    }
                    Picker("Job", selection: $selectedJobID) {
                        Text("No job").tag(Int64(0))
                        ForEach(activeJobsForCustomer) { job in
                            Text(job.displayName).tag(job.id)
                        }
                    }
                    .disabled(selectedCustomerID == 0 || activeJobsForCustomer.isEmpty)
                    Text("Assigning a job lets this bill flow into job profitability. When paid, the check/register expense keeps the same job.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)
            .onChange(of: selectedCustomerID) { _ in
                selectedJobID = 0
            }

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundStyle(AppTheme.bad).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                SaveSplitButton(
                    isEditing: false,
                    canSave: canSave,
                    onSaveAndClose: {
                        if saveBill() { dismiss() }
                    },
                    onSaveAndNew: {
                        if saveBill() { resetForNewBill() }
                    }
                )
            }
            .padding()
        }
        .frame(width: 460, height: 520)
    }

    private func saveBill() -> Bool {
        guard let amt = Double(trimmedAmount), amt > 0 else {
            errorMessage = "Enter a valid amount."
            return false
        }
        guard selectedAccountID != 0 else {
            errorMessage = "Pick an expense category — bills must post to an account."
            return false
        }
        let fmt = DateFormatter.isoDate
        let vendorIDOpt: Int64? = selectedVendorID == 0 ? nil : selectedVendorID
        do {
            try model.db.insertBill(
                vendorNameOverride: vendorName,
                vendorID: vendorIDOpt,
                billDate: fmt.string(from: billDate),
                dueDate: fmt.string(from: dueDate),
                amount: amt,
                accountID: selectedAccountID,
                jobID: selectedJobID == 0 ? nil : selectedJobID,
                memo: memo
            )
            onSave()
            return true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func resetForNewBill() {
        vendorName = ""
        selectedVendorID = 0
        billDate = Date()
        dueDate = Date().addingTimeInterval(14 * 86400)
        amount = ""
        selectedAccountID = 0
        selectedCustomerID = 0
        selectedJobID = 0
        memo = ""
        errorMessage = ""
    }
}

struct RecordDepositSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var onSave: () -> Void

    @State private var depositDate = Date()
    @State private var destinationAccountID: Int64 = 0
    @State private var reference = ""
    @State private var memo = ""
    @State private var undepositedPayments: [PaymentReceivedRow] = []
    @State private var selectedPaymentIDs: Set<Int64> = []
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    private var depositAccounts: [AccountRow] {
        model.accounts.filter {
            $0.type == "asset" && $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        }
    }

    private var selectedTotal: Double {
        undepositedPayments.filter { selectedPaymentIDs.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Record Deposit")
                .font(.title2.bold())
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deposit Date").font(.caption).foregroundStyle(AppTheme.ink3)
                        SmartDateField(date: $depositDate)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deposit Account").font(.caption).foregroundStyle(AppTheme.ink3)
                        Picker("", selection: $destinationAccountID) {
                            Text("- Select Account -").tag(Int64(0))
                            ForEach(depositAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        .frame(width: 260)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference").font(.caption).foregroundStyle(AppTheme.ink3)
                        TextField("Deposit reference", text: $reference)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Memo").font(.caption).foregroundStyle(AppTheme.ink3)
                    TextField("Memo", text: $memo)
                        .textFieldStyle(.roundedBorder)
                }

                if undepositedPayments.isEmpty {
                    Text("No undeposited customer payments are waiting to be grouped into a deposit.")
                        .foregroundStyle(AppTheme.ink3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panel)
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("").frame(width: 34)
                            Text("Date").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                            Text("Customer").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Invoice").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 130, alignment: .leading)
                            Text("Method").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .leading)
                            Text("Amount").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface)

                        ForEach(undepositedPayments) { payment in
                            HStack(spacing: 0) {
                                Toggle("", isOn: Binding(
                                    get: { selectedPaymentIDs.contains(payment.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedPaymentIDs.insert(payment.id)
                                        } else {
                                            selectedPaymentIDs.remove(payment.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .frame(width: 34)
                                Text(payment.paymentDate)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 100, alignment: .leading)
                                Text(payment.customerDisplayName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(payment.invoiceNumber.isEmpty ? "-" : payment.invoiceNumber)
                                    .frame(width: 130, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(payment.method)
                                    .frame(width: 110, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(billCurrency(payment.amount))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .background(AppTheme.panel)
                    .cornerRadius(8)
                }

                HStack {
                    Spacer()
                    Text("Selected Total: \(billCurrency(selectedTotal))")
                        .font(.headline)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(AppTheme.bad).font(.caption)
                }
            }
            .padding()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Record Deposit") { saveDeposit() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(selectedPaymentIDs.isEmpty || destinationAccountID == 0)
            }
            .padding()
        }
        .frame(width: 860, height: 620)
        .onAppear { loadPayments() }
        .accessibilityIdentifier("deposits.recordSheet")
    }

    private func loadPayments() {
        undepositedPayments = (try? model.db.fetchUndepositedPayments()) ?? []
        let savedDefault = model.paymentWorkflowSettings.defaultDepositAccountID
        if destinationAccountID == 0 {
            if savedDefault != 0, depositAccounts.contains(where: { $0.id == savedDefault }) {
                destinationAccountID = savedDefault
            } else {
                destinationAccountID = depositAccounts.first?.id ?? 0
            }
        }
    }

    private func saveDeposit() {
        do {
            _ = try model.db.recordDeposit(
                paymentIDs: Array(selectedPaymentIDs),
                depositDate: DateFormatter.isoDate.string(from: depositDate),
                destinationAccountID: destinationAccountID,
                reference: reference,
                memo: memo
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = "Could not record deposit: \(error.localizedDescription)"
        }
    }
}

struct PayBillsSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var preselectedBillIDs: Set<Int64> = []
    var onSave: () -> Void

    @State private var paymentDate = Date()
    @State private var paymentMethod = "Check"
    @State private var paymentAccountID: Int64 = 0
    @State private var startingCheckNumber = ""
    @State private var memo = ""
    @State private var selectedBillIDs: Set<Int64> = []
    @State private var unpaidBills: [BillRow] = []
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    private var paymentMethodOptions: [String] {
        var options = model.paymentMethods.map(\.name)
        for fallback in ["Check", "ACH", "Bank Transfer", "Credit Card", "Cash", "Other"] where !options.contains(fallback) {
            options.append(fallback)
        }
        return options
    }

    private var bankAccounts: [AccountRow] {
        model.accounts.filter {
            $0.type == "asset" && $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        }
    }

    private var selectedTotal: Double {
        unpaidBills.filter { selectedBillIDs.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pay Bills")
                .font(.title2.bold())
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Payment Date").font(.caption).foregroundStyle(AppTheme.ink3)
                        SmartDateField(date: $paymentDate)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Method").font(.caption).foregroundStyle(AppTheme.ink3)
                        Picker("", selection: $paymentMethod) {
                            ForEach(paymentMethodOptions, id: \.self) { method in
                                Text(method).tag(method)
                            }
                        }
                        .frame(width: 180)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paid From").font(.caption).foregroundStyle(AppTheme.ink3)
                        Picker("", selection: $paymentAccountID) {
                            Text("- Select Account -").tag(Int64(0))
                            ForEach(bankAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        .frame(width: 240)
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Starting Check #").font(.caption).foregroundStyle(AppTheme.ink3)
                        TextField("Optional", text: $startingCheckNumber)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .disabled(paymentMethod.caseInsensitiveCompare("Check") != .orderedSame)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Memo").font(.caption).foregroundStyle(AppTheme.ink3)
                        TextField("Memo", text: $memo)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 340)
                    }
                }

                if unpaidBills.isEmpty {
                    Text("No unpaid bills are available.")
                        .foregroundStyle(AppTheme.ink3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panel)
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("").frame(width: 34)
                            Text("Vendor").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Due").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                            Text("Category").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 180, alignment: .leading)
                            Text("Amount").font(.caption.bold()).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface)

                        ForEach(unpaidBills) { bill in
                            HStack(spacing: 0) {
                                Toggle("", isOn: Binding(
                                    get: { selectedBillIDs.contains(bill.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedBillIDs.insert(bill.id)
                                        } else {
                                            selectedBillIDs.remove(bill.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.displayVendorName)
                                    if !bill.displayMemo.isEmpty {
                                        Text(bill.displayMemo).font(.caption).foregroundStyle(AppTheme.ink3)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(bill.dueDate)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 100, alignment: .leading)
                                Text(bill.accountName)
                                    .frame(width: 180, alignment: .leading)
                                    .foregroundStyle(AppTheme.ink3)
                                Text(billCurrency(bill.amount))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .background(AppTheme.panel)
                    .cornerRadius(8)
                }

                HStack {
                    Spacer()
                    Text("Selected Bills: \(selectedBillIDs.count)  •  Total: \(billCurrency(selectedTotal))")
                        .font(.headline)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(AppTheme.bad).font(.caption)
                }
            }
            .padding()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Pay Selected Bills") { payBills() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(selectedBillIDs.isEmpty || paymentAccountID == 0)
            }
            .padding()
        }
        .frame(width: 880, height: 640)
        .onAppear { loadBills() }
        .onChange(of: paymentMethod) { newMethod in
            guard newMethod.caseInsensitiveCompare("Check") == .orderedSame else {
                startingCheckNumber = ""
                return
            }
            if paymentAccountID != 0 {
                startingCheckNumber = model.nextCheckNumber(paymentAccountID: paymentAccountID)
            }
        }
        .onChange(of: paymentAccountID) { newAccountID in
            guard newAccountID != 0 else { return }
            guard paymentMethod.caseInsensitiveCompare("Check") == .orderedSame else { return }
            startingCheckNumber = model.nextCheckNumber(paymentAccountID: newAccountID)
        }
        .accessibilityIdentifier("bills.paySheet")
    }

    private func loadBills() {
        unpaidBills = (try? model.db.fetchBills(unpaidOnly: true)) ?? []
        selectedBillIDs = preselectedBillIDs
        if paymentAccountID == 0 {
            paymentAccountID = bankAccounts.first?.id ?? 0
        }
        if startingCheckNumber.isEmpty, paymentMethod.caseInsensitiveCompare("Check") == .orderedSame, paymentAccountID != 0 {
            startingCheckNumber = model.nextCheckNumber(paymentAccountID: paymentAccountID)
        }
    }

    private func payBills() {
        do {
            try model.db.recordBillPayments(
                billIDs: Array(selectedBillIDs),
                paymentDate: DateFormatter.isoDate.string(from: paymentDate),
                paymentAccountID: paymentAccountID == 0 ? nil : paymentAccountID,
                paymentMethod: paymentMethod,
                startingCheckNumber: startingCheckNumber,
                memo: memo
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = "Could not pay bills: \(error.localizedDescription)"
        }
    }
}

private func billCurrency(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
