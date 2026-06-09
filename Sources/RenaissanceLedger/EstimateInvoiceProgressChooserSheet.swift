import SwiftUI

struct EstimateInvoiceProgressChooserSheet: View {
    let estimate: EstimateRow
    let progress: EstimateProgressSnapshot
    let loadLines: () throws -> [EstimateLineRow]
    let onStart: (EstimateInvoiceProgressSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection = EstimateInvoiceProgressSelection()
    @State private var lines: [EstimateLineRow] = []
    @State private var loadError = ""

    private var canStart: Bool {
        switch selection.mode {
        case .fullRemaining:
            return progress.hasRemainingBalance
        case .percentOfEstimate:
            return selection.percentValue > 0
        case .selectedLines:
            return !selectedLines.isEmpty
        }
    }

    private var selectedLines: [EstimateLineRow] {
        lines.filter { selection.selectedEstimateLineIDs.contains($0.id) }
    }

    private var selectedTotal: Double {
        switch selection.mode {
        case .fullRemaining:
            return progress.remainingTotal
        case .percentOfEstimate:
            return estimate.total * max(0, selection.percentValue) / 100
        case .selectedLines:
            return selectedLines.reduce(0) { $0 + $1.amount }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invoice From Estimate")
                        .font(.title2.bold())
                    Text("Estimate \(estimate.estimateNumber)")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink3)
                    Text("Choose how much of this estimate should become the new invoice.")
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
                    Picker("Mode", selection: $selection.mode) {
                        ForEach(EstimateInvoiceProgressMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estimate Progress")
                            .font(.headline)
                        HStack(spacing: 16) {
                            chooserStat("Estimate Total", estimateCurrency(progress.estimateTotal))
                            chooserStat("Already Invoiced", estimateCurrency(progress.invoicedTotal))
                            chooserStat("Remaining", estimateCurrency(progress.remainingTotal))
                        }
                        if !progress.hasRemainingBalance {
                            Text("This estimate has no remaining balance left to invoice.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }
                    }

                    if selection.mode == .percentOfEstimate {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Percentage")
                                .font(.headline)
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: { selection.percentValue },
                                        set: { selection.percentValue = min(max($0, 1), 100) }
                                    ),
                                    in: 1...100,
                                    step: 1
                                )
                                Text("\(selection.percentDisplayValue)%")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 56, alignment: .trailing)
                            }
                            Text("Each estimate line keeps its quantity, and the invoice rate is scaled to the chosen percentage.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }
                    }

                    if selection.mode == .selectedLines {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Select Estimate Lines")
                                .font(.headline)

                            if lines.isEmpty {
                                Text("No estimate lines are available.")
                                    .foregroundStyle(AppTheme.ink3)
                            } else {
                                ForEach(lines) { line in
                                    Button {
                                        toggleLine(line.id)
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: selection.selectedEstimateLineIDs.contains(line.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selection.selectedEstimateLineIDs.contains(line.id) ? AppTheme.accent : AppTheme.secondaryText)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(line.description)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                Text("Qty \(String(format: "%.2f", line.quantity))  |  Rate \(estimateCurrency(line.rate))  |  Amount \(estimateCurrency(line.amount))")
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.ink3)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(AppTheme.canvas)
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !loadError.isEmpty {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.bad)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invoice Preview")
                            .font(.headline)
                        HStack(spacing: 16) {
                            chooserStat("Mode", selection.mode.title)
                            chooserStat("Lines", "\(previewLineCount)")
                            chooserStat("Estimated Total", estimateCurrency(selectedTotal))
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Start Invoice") {
                    dismiss()
                    onStart(selection)
                }
                .buttonStyle(.renaissancePrimary)
                .disabled(!canStart)
            }
            .padding()
        }
        .frame(width: 700, height: 560)
        .onAppear(perform: loadEstimateLines)
    }

    private var previewLineCount: Int {
        switch selection.mode {
        case .fullRemaining, .percentOfEstimate:
            return lines.count
        case .selectedLines:
            return selectedLines.count
        }
    }

    private func loadEstimateLines() {
        do {
            lines = try loadLines()
            if selection.selectedEstimateLineIDs.isEmpty {
                selection.selectedEstimateLineIDs = Set(lines.map(\.id))
            }
        } catch {
            loadError = "Could not load estimate lines: \(error.localizedDescription)"
        }
    }

    private func toggleLine(_ id: Int64) {
        if selection.selectedEstimateLineIDs.contains(id) {
            selection.selectedEstimateLineIDs.remove(id)
        } else {
            selection.selectedEstimateLineIDs.insert(id)
        }
    }

    private func chooserStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(value)
                .font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .cornerRadius(10)
    }
}
