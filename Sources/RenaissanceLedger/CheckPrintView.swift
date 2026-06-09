import AppKit
import SwiftUI

struct CheckPrintView: View {
    let draft: CheckDraft
    var companyInfo: CompanyInfo = CompanyInfo()
    var workflowSettings: CheckWorkflowSettings = .load()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            checkFace
            Divider()
            stubSection(title: "Voucher Stub")
            Divider()
            stubSection(title: "Accounting Copy")
        }
        .padding(24)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
        .font(.system(size: 11))
        .environment(\.colorScheme, .light)
    }

    private var checkFace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companyInfo.name)
                        .font(.system(size: 18, weight: .bold))
                    if !companyInfo.address1.isEmpty {
                        Text(companyInfo.address1)
                    }
                    if !companyInfo.cityStateZip.isEmpty {
                        Text(companyInfo.cityStateZip)
                    }
                    if !companyInfo.phone.isEmpty {
                        Text(companyInfo.phone)
                    }
                }
                .font(.system(size: 9))

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("CHECK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("No.")
                            .foregroundStyle(.secondary)
                        Text(draft.checkNumber.isEmpty ? "Pending" : draft.checkNumber)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Date")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                lineFill(text: checkDisplayDate(draft.expenseDate))
                Spacer(minLength: 24)
                amountBox
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Pay to the Order of")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                lineFill(text: draft.payeeName.isEmpty ? " " : draft.payeeName)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Amount")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                lineFill(text: amountInWords(draft.amount))
                Text("Dollars")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 18) {
                if workflowSettings.showMemoOnPrintedChecks {
                    labeledLine("Memo", value: draft.memo.isEmpty ? draft.detailSummary : draft.memo)
                }
                if workflowSettings.showCategoryOnPrintedChecks {
                    labeledLine("Category", value: draft.categoryName)
                }
                if !draft.detailSummary.isEmpty {
                    labeledLine(draft.itemLines.isEmpty ? "Detail" : "Items", value: draft.detailSummary)
                }
                labeledLine("Paid From", value: draft.bankAccountName)
            }

            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 210, height: 1)
                    Text("Authorized Signature")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        }
        .padding(.bottom, 8)
    }

    private var amountBox: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
            Text(checkCurrency(draft.amount))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 1)
        )
    }

    private func stubSection(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                Text("Check \(draft.checkNumber.isEmpty ? "Pending" : draft.checkNumber)")
                    .font(.system(size: 10, design: .monospaced))
            }

            HStack(spacing: 18) {
                stubField("Date", checkDisplayDate(draft.expenseDate))
                stubField("Payee", draft.payeeName)
                stubField("Amount", "$" + checkCurrency(draft.amount))
            }

            HStack(spacing: 18) {
                if workflowSettings.showCategoryOnPrintedChecks {
                    stubField("Category", draft.categoryName)
                }
                stubField("Paid From", draft.bankAccountName)
                if workflowSettings.showMemoOnPrintedChecks {
                    stubField("Memo", draft.memo)
                }
                if !draft.detailSummary.isEmpty {
                    stubField(draft.itemLines.isEmpty ? "Detail" : "Items", draft.detailSummary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func lineFill(text: String) -> some View {
        VStack(spacing: 4) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(height: 1)
        }
    }

    private func labeledLine(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            lineFill(text: value.isEmpty ? " " : value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stubField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func printCheck(_ draft: CheckDraft, companyInfo: CompanyInfo, workflowSettings: CheckWorkflowSettings = .load()) {
    let hostView = NSHostingView(rootView: CheckPrintView(draft: draft, companyInfo: companyInfo, workflowSettings: workflowSettings))
    hostView.frame = CGRect(x: 0, y: 0, width: 612, height: 792)

    let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
    printInfo.paperSize = NSSize(width: 612, height: 792)
    printInfo.topMargin = 18
    printInfo.bottomMargin = 18
    printInfo.leftMargin = 18
    printInfo.rightMargin = 18
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .fit
    printInfo.isHorizontallyCentered = false
    printInfo.isVerticallyCentered = false

    let operation = NSPrintOperation(view: hostView, printInfo: printInfo)
    operation.jobTitle = draft.checkNumber.isEmpty ? "Check" : "Check \(draft.checkNumber)"
    operation.run()
}

private func checkCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
}

func amountInWords(_ amount: Double) -> String {
    let whole = Int(amount.rounded(.down))
    let cents = Int((amount - Double(whole)).rounded(toPlaces: 2) * 100)
    let formatter = NumberFormatter()
    formatter.numberStyle = .spellOut
    let words = formatter.string(from: NSNumber(value: whole))?.capitalized ?? "\(whole)"
    return "\(words) and \(String(format: "%02d", cents))/100"
}

func checkDisplayDate(_ isoDate: String) -> String {
    if let date = DateFormatter.isoDate.date(from: isoDate) {
        return CheckPrintDateFormatter.shared.string(from: date)
    }
    return isoDate
}

private final class CheckPrintDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
