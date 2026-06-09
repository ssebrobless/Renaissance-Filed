import SwiftUI

struct VendorsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showAddSheet = false
    @State private var editingVendor: VendorRow?
    @State private var search = ""
    @State private var sortMode: EntityListSortMode = .alphabeticalAsc
    @State private var initialFilter = "All"
    @State private var dateFilterMode: EntityDateFilterMode = .allTime
    @State private var customFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customToDate = Date()

    private var filtered: [VendorRow] {
        let searched = model.vendors.filter {
            guard !search.isEmpty else { return true }
            return $0.name.localizedCaseInsensitiveContains(search)
                || $0.company.localizedCaseInsensitiveContains(search)
                || $0.primaryContact.localizedCaseInsensitiveContains(search)
                || $0.phone.contains(search)
        }

        let narrowed = searched.filter { vendor in
            (initialFilter == "All" || entityInitialBucket(for: vendor.displayName) == initialFilter)
                && entityDateMatches(
                    createdAt: vendor.createdAt,
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

    private var flaggedInternal1099Vendors: [VendorRow] {
        model.vendors.filter { $0.is1099 && reviewContext(for: $0).isInternalSelf }
    }

    private func reviewContext(for vendor: VendorRow) -> PayeeReviewContext {
        payeeReviewContext(for: vendor.name, vendors: model.vendors, companyInfo: model.companyInfo)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payees & Vendors")
                            .font(.title2.bold())
                        Text("This list includes any named payee used on checks and expenses, not only subcontractors.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Spacer()
                    Button("+ Add Payee") { showAddSheet = true }
                        .buttonStyle(.renaissancePrimary)
                }

                HStack(spacing: 12) {
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

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

            Divider()

            if !flaggedInternal1099Vendors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Review internal/self payees marked as 1099 vendors.", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.warn)
                    Text(flaggedInternal1099Vendors.map(\.displayLabel).joined(separator: ", ") + ". These payees match the company phone or an internal/self alias. Keep the historical checks, but review whether the 1099 toggle should stay on before relying on current-year 1099 review.")
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
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()
            }

            HStack(spacing: 0) {
                Text("Name").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Company").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 200, alignment: .leading)
                Text("Contact").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 160, alignment: .leading)
                Text("Phone").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 130, alignment: .leading)
                Text("EIN").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .leading)
                Text("1099").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 50, alignment: .center)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.vendors.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "building.2").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Payees Yet").font(.title2)
                    Text("Add payees or vendors to track subcontractors, suppliers, cards, and other expense recipients.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { vendor in
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vendor.displayLabel)
                            Text(reviewContext(for: vendor).kind.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(reviewContext(for: vendor).kind == .internalSelf ? AppTheme.warn : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(vendor.company)
                            .frame(width: 200, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(vendor.primaryContact)
                            .frame(width: 160, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(vendor.phone)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 130, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(vendor.ein)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 110, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Image(systemName: vendor.is1099 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(vendor.is1099 ? AppTheme.ok : .secondary)
                            .frame(width: 50, alignment: .center)
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { editingVendor = vendor }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            VendorSheet(vendor: nil) {
                showAddSheet = false
                model.refreshVendors()
            }
            .environmentObject(model)
        }
        .sheet(item: $editingVendor) { vendor in
            VendorSheet(vendor: vendor) {
                editingVendor = nil
                model.refreshVendors()
            }
            .environmentObject(model)
        }
    }
}

struct VendorSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let vendor: VendorRow?
    var onSave: () -> Void

    @State private var name = ""
    @State private var company = ""
    @State private var primaryContact = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var ein = ""
    @State private var is1099 = false
    @State private var isInternalSelf = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { vendor != nil }
    private var title: String { isEditing ? "Edit Payee / Vendor" : "Add Payee / Vendor" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                Section("Contact") {
                    TextField("Name *", text: $name)
                    TextField("Company", text: $company)
                    TextField("Primary Contact", text: $primaryContact)
                    TextField("Phone", text: $phone)
                }
                Section("Address") {
                    TextField("Street Address", text: $address)
                }
                Section("Tax Info") {
                    HStack {
                        Text("EIN / Tax ID")
                        Spacer()
                        TextField("XX-XXXXXXX", text: $ein)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    Toggle("Track as 1099 subcontractor", isOn: $is1099)
                    Toggle("Mark as internal / self payee", isOn: $isInternalSelf)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundStyle(AppTheme.bad).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isEditing ? "Save Changes" : "Add Payee") { save() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .onAppear {
            if let v = vendor {
                name = v.name
                company = v.company
                primaryContact = v.primaryContact
                phone = v.phone
                address = v.address
                ein = v.ein
                is1099 = v.is1099
                isInternalSelf = v.isInternalSelf
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Name is required."
            return
        }
        if let v = vendor {
            model.updateVendor(id: v.id, name: trimmed, company: company, primaryContact: primaryContact, phone: phone,
                               address: address, ein: ein, is1099: is1099, isInternalSelf: isInternalSelf)
        } else {
            model.addVendor(name: trimmed, company: company, primaryContact: primaryContact, phone: phone,
                            address: address, ein: ein, is1099: is1099, isInternalSelf: isInternalSelf)
        }
        onSave()
    }
}
