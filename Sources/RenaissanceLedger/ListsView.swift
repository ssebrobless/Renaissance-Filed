import SwiftUI

struct ListsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var selectedSection = "terms"

    private let archivedDocumentNames: [String] = [
        "List_Payroll_Items.pdf",
        "Financial_Trial_Balance.pdf",
        "Financial_Cash_Flows.pdf",
        "Sales_By_Item_Summary.pdf",
        "Sales_By_Item_Detail.pdf",
        "Sales_By_Rep_Summary.pdf",
        "Sales_By_Rep_Detail.pdf",
        "Banking_Missing_Checks.pdf"
    ]

    private var archivedReferences: [DocumentRow] {
        model.documents
            .filter { archivedDocumentNames.contains($0.documentFileName) }
            .sorted { $0.documentFileName.localizedCaseInsensitiveCompare($1.documentFileName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lists & QB References")
                            .font(.title2.bold())
                        Text("Structured QuickBooks lists now native here, with quick access to archived QB-only report surfaces.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Spacer()
                }

                Picker("Section", selection: $selectedSection) {
                    Text("Terms").tag("terms")
                    Text("Payment Methods").tag("paymentMethods")
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if selectedSection == "terms" {
                        termsTable
                    } else {
                        paymentMethodsTable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                archivedReferencePanel
                    .frame(width: 320)
            }
        }
    }

    private var termsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Name").font(.caption).foregroundStyle(AppTheme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                header("Ref", width: 48, alignment: .leading)
                header("Due", width: 64, alignment: .trailing)
                header("Disc %", width: 64, alignment: .trailing)
                header("Disc Days", width: 80, alignment: .trailing)
                header("Type", width: 64, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.paymentTerms.isEmpty {
                emptyState(title: "No Payment Terms", message: "No imported QuickBooks payment terms are available yet.")
            } else {
                List(model.paymentTerms) { term in
                    HStack(spacing: 14) {
                        Text(term.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text(term.refnum).frame(width: 48, alignment: .leading).foregroundStyle(AppTheme.ink3)
                        Text(term.dueDays == 0 ? "Receipt" : "\(term.dueDays)")
                            .frame(width: 64, alignment: .trailing)
                        Text(term.discountPercent == 0 ? "-" : String(format: "%.2f", term.discountPercent))
                            .frame(width: 64, alignment: .trailing)
                        Text(term.discountDays == 0 ? "-" : "\(term.discountDays)")
                            .frame(width: 80, alignment: .trailing)
                        Text(term.termsType).frame(width: 64, alignment: .leading).foregroundStyle(AppTheme.ink3)
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
        }
    }

    private var paymentMethodsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("Name", width: 220, alignment: .leading)
                header("Ref", width: 60, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.paymentMethods.isEmpty {
                emptyState(title: "No Payment Methods", message: "No imported QuickBooks payment methods are available yet.")
            } else {
                List(model.paymentMethods) { method in
                    HStack(spacing: 0) {
                        Text(method.name).frame(width: 220, alignment: .leading)
                        Text(method.refnum).frame(width: 60, alignment: .leading).foregroundStyle(AppTheme.ink3)
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
        }
    }

    private var archivedReferencePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archived QB References")
                .font(.headline)
            Text("These still come from preserved QuickBooks source documents. They are useful for audit and comparison even before full native parsing.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)

            if archivedReferences.isEmpty {
                Spacer()
                Text("No archived QB reference documents found.")
                    .foregroundStyle(AppTheme.ink3)
                Spacer()
            } else {
                List(archivedReferences) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.documentFileName)
                            .font(.subheadline.bold())
                            .lineLimit(2)
                        HStack(spacing: 10) {
                            Button("Open") { model.openDocument(row) }
                                .buttonStyle(.borderless)
                            Button("Email") { model.emailDocument(row) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
    }

    private func header(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.ink3)
            .frame(width: width, alignment: alignment)
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.ink3)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .foregroundStyle(AppTheme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
