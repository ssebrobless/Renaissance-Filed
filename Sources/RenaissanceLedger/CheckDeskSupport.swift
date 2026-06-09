import SwiftUI

enum CheckDeskSource: Hashable {
    case draft
    case expense(Int64)
}

struct CheckDeskItem: Identifiable {
    let id: UUID
    var source: CheckDeskSource
    var title: String
    var subtitle: String
    var draft: CheckDraft
    var isSaved: Bool
    var updatedAt: Date

    var stackLabel: String {
        let number = draft.checkNumber.isEmpty ? "Draft" : "#\(draft.checkNumber)"
        return "\(number) \(draft.payeeName.isEmpty ? "Blank Check" : draft.payeeName)"
    }
}

@MainActor
final class CheckDeskSession: ObservableObject {
    @Published private(set) var stack: [CheckDeskItem] = []
    @Published var activeID: UUID?
    @Published var isStackListVisible = false
    @Published var selectedVisibleIDs: Set<UUID> = []

    var activeItem: CheckDeskItem? {
        guard let activeID else { return stack.first }
        return stack.first { $0.id == activeID } ?? stack.first
    }

    var activeIndexText: String {
        guard let activeItem,
              let index = stack.firstIndex(where: { $0.id == activeItem.id }) else {
            return "No checks"
        }
        return "Check \(index + 1) of \(stack.count)"
    }

    var visibleItems: [CheckDeskItem] {
        guard isStackListVisible, !selectedVisibleIDs.isEmpty else {
            return activeItem.map { [$0] } ?? []
        }
        let selected = stack.filter { selectedVisibleIDs.contains($0.id) }
        return selected.isEmpty ? activeItem.map { [$0] } ?? [] : selected
    }

    func openNew(defaultBankAccountName: String) {
        let item = CheckDeskItem(
            id: UUID(),
            source: .draft,
            title: "New Check Draft",
            subtitle: "Unsaved desk check",
            draft: CheckDraft(
                payeeName: "",
                checkNumber: "",
                expenseDate: DateFormatter.isoDate.string(from: Date()),
                amount: 0,
                memo: "",
                categoryName: "",
                bankAccountName: defaultBankAccountName
            ),
            isSaved: false,
            updatedAt: Date()
        )
        addOrActivate(item)
    }

    func openExpense(_ expense: ExpenseRow) {
        let source = CheckDeskSource.expense(expense.id)
        let item = CheckDeskItem(
            id: existingID(for: source) ?? UUID(),
            source: source,
            title: expense.checkNumber.isEmpty ? "Expense \(expense.id)" : "Check #\(expense.checkNumber)",
            subtitle: expense.displayVendorName,
            draft: CheckDraft(
                payeeName: expense.displayVendorName,
                checkNumber: expense.checkNumber,
                expenseDate: expense.expenseDate,
                amount: expense.amount,
                memo: expense.displayMemo,
                categoryName: expense.accountName,
                bankAccountName: expense.paymentAccountName,
                detailSummary: expense.accountName
            ),
            isSaved: true,
            updatedAt: Date()
        )
        addOrActivate(item)
    }

    func cyclePrevious() {
        cycle(delta: -1)
    }

    func cycleNext() {
        cycle(delta: 1)
    }

    func removeActive() {
        guard let activeItem else { return }
        stack.removeAll { $0.id == activeItem.id }
        selectedVisibleIDs.remove(activeItem.id)
        activeID = stack.first?.id
        if let activeID, selectedVisibleIDs.isEmpty {
            selectedVisibleIDs.insert(activeID)
        }
    }

    func toggleVisible(_ item: CheckDeskItem) {
        if selectedVisibleIDs.contains(item.id) {
            selectedVisibleIDs.remove(item.id)
        } else {
            selectedVisibleIDs.insert(item.id)
        }
        activeID = item.id
        if selectedVisibleIDs.isEmpty {
            selectedVisibleIDs.insert(item.id)
        }
    }

    func activate(_ item: CheckDeskItem) {
        activeID = item.id
        if !isStackListVisible {
            selectedVisibleIDs = [item.id]
        } else if selectedVisibleIDs.isEmpty {
            selectedVisibleIDs.insert(item.id)
        }
    }

    private func addOrActivate(_ item: CheckDeskItem) {
        if let index = stack.firstIndex(where: { $0.source == item.source }) {
            stack[index] = item
        } else {
            stack.append(item)
        }
        activeID = item.id
        selectedVisibleIDs = [item.id]
    }

    private func existingID(for source: CheckDeskSource) -> UUID? {
        stack.first { $0.source == source }?.id
    }

    private func cycle(delta: Int) {
        guard !stack.isEmpty else { return }
        let currentIndex = activeItem.flatMap { active in stack.firstIndex(where: { $0.id == active.id }) } ?? 0
        let nextIndex = (currentIndex + delta + stack.count) % stack.count
        activate(stack[nextIndex])
    }
}

struct CheckDeskWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @EnvironmentObject private var checkDesk: CheckDeskSession
    @EnvironmentObject private var windowManager: WorkspaceWindowManager

    private let checkSize = CGSize(width: 720, height: 295)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if checkDesk.visibleItems.isEmpty {
                emptyState
            } else {
                deskSurface
            }
        }
        .frame(width: 880, height: 430)
        .background(AppTheme.canvas)
        .onAppear {
            if checkDesk.stack.isEmpty {
                checkDesk.openNew(defaultBankAccountName: defaultBankAccountName)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check Desk")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(checkDesk.activeIndexText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
            Spacer()
            Button {
                checkDesk.cyclePrevious()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(checkDesk.stack.count < 2)
            Button {
                checkDesk.cycleNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(checkDesk.stack.count < 2)
            Button {
                checkDesk.isStackListVisible.toggle()
                if checkDesk.isStackListVisible, let active = checkDesk.activeItem {
                    checkDesk.selectedVisibleIDs.insert(active.id)
                }
            } label: {
                Label(checkDesk.isStackListVisible ? "Standard View" : "Stack List", systemImage: "checklist")
            }
            Button(role: .destructive) {
                checkDesk.removeActive()
            } label: {
                Label("Remove", systemImage: "xmark.circle")
            }
            .disabled(checkDesk.activeItem == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
    }

    private var deskSurface: some View {
        HStack(spacing: 0) {
            if checkDesk.isStackListVisible {
                stackList
                    .frame(width: 260)
                Divider()
            }

            if !checkDesk.isStackListVisible, let active = checkDesk.activeItem {
                VStack(alignment: .leading, spacing: 0) {
                    deskCheckCard(active)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(checkDesk.visibleItems) { item in
                            deskCheckCard(item)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var stackList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checks on Desk")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink3)
            ForEach(checkDesk.stack) { item in
                Button {
                    checkDesk.toggleVisible(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: checkDesk.selectedVisibleIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checkDesk.activeItem?.id == item.id ? AppTheme.accent : AppTheme.ink3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.stackLabel)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(item.subtitle.isEmpty ? (item.isSaved ? "Saved check" : "Unsaved draft") : item.subtitle)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.ink3)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(checkDesk.activeItem?.id == item.id ? AppTheme.panel : AppTheme.cardFillSoft)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Checking multiple boxes lines checks up side-by-side for comparison.")
                .font(.caption2)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(14)
        .background(AppTheme.surface)
    }

    private func deskCheckCard(_ item: CheckDeskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            realisticCheck(item.draft)
                .frame(width: checkSize.width, height: checkSize.height)
                .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
                .onTapGesture {
                    checkDesk.activate(item)
                }

            HStack {
                Label(item.isSaved ? "Saved ledger check" : "Draft not saved", systemImage: item.isSaved ? "checkmark.seal.fill" : "pencil.and.outline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isSaved ? AppTheme.ok : AppTheme.warn)
                Spacer()
                Button("Open Full Editor") {
                    windowManager.openNavigatorRoute(.expenses)
                }
                .controlSize(.small)
            }
            .frame(width: checkSize.width)
        }
    }

    private func realisticCheck(_ draft: CheckDraft) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.paper)
            checkWatermark
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.companyInfo.name.isEmpty ? "Your Company Name" : model.companyInfo.name)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                        Text(draft.bankAccountName.isEmpty ? defaultBankAccountName : draft.bankAccountName)
                            .font(.caption)
                            .foregroundStyle(.brown.opacity(0.72))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(deskCheckDisplayDate(draft.expenseDate))
                            .font(.system(size: 13, design: .monospaced))
                        Text(draft.checkNumber.isEmpty ? "Draft" : "No. \(draft.checkNumber)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("PAY TO THE ORDER OF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(.brown.opacity(0.70))
                    Text(draft.payeeName.isEmpty ? " " : draft.payeeName)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(.brown.opacity(0.25)).frame(height: 1)
                        }
                    amountBox(draft.amount)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(checkAmountWords(draft.amount))
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(.brown.opacity(0.18)).frame(height: 1)
                        }
                    Text("DOLLARS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.brown.opacity(0.70))
                }

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MEMO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(.brown.opacity(0.65))
                        Text(draft.memo.isEmpty ? draft.detailSummary : draft.memo)
                            .font(.caption)
                            .frame(width: 280, alignment: .leading)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(.brown.opacity(0.18)).frame(height: 1)
                            }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Rectangle().fill(.brown.opacity(0.45)).frame(width: 220, height: 1)
                        Text("AUTHORIZED SIGNATURE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(.brown.opacity(0.64))
                    }
                }
            }
            .padding(26)
        }
        .foregroundStyle(.black.opacity(0.86))
        .environment(\.colorScheme, .light)
    }

    private var checkWatermark: some View {
            Text("RT")
            .font(.system(size: 132, weight: .bold, design: .serif))
            .foregroundStyle(Color.orange.opacity(0.06))
            .rotationEffect(.degrees(-8))
            .frame(width: checkSize.width, height: checkSize.height, alignment: .center)
            .allowsHitTesting(false)
    }

    private func amountBox(_ amount: Double) -> some View {
        HStack(spacing: 10) {
            Text("$")
            Text(checkCurrencyText(amount))
        }
        .font(.system(size: 18, weight: .bold, design: .monospaced))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(width: 170, alignment: .trailing)
        .background(Color.brown.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.brown.opacity(0.35), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkbook")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.ink3)
            Text("No checks on the desk")
                .font(.title3.bold())
            Button("Start a Draft Check") {
                checkDesk.openNew(defaultBankAccountName: defaultBankAccountName)
            }
            .buttonStyle(.renaissancePrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas)
    }

    private var defaultBankAccountName: String {
        model.accounts.first { $0.type == "asset" && $0.name.localizedCaseInsensitiveContains("checking") }?.name
            ?? model.accounts.first { $0.type == "asset" }?.name
            ?? "Checking Account"
    }
}

private func checkCurrencyText(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
}

private func deskCheckDisplayDate(_ raw: String) -> String {
    guard let date = DateFormatter.isoDate.date(from: raw) else { return raw }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

private func checkAmountWords(_ amount: Double) -> String {
    guard amount > 0 else { return "Zero and 00/100" }
    let dollars = Int(amount.rounded(.towardZero))
    let cents = Int(round((amount - Double(dollars)) * 100))
    let formatter = NumberFormatter()
    formatter.numberStyle = .spellOut
    let words = formatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
    return "\(words.capitalized) and \(String(format: "%02d", cents))/100"
}
