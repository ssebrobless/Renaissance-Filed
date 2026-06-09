import Foundation
import SwiftUI

enum MemorizedTransactionCodec {
    static func encode<Payload: Encodable>(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MemorizedTransactionCodec", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode memorized transaction payload."])
        }
        return json
    }

    static func decode<Payload: Decodable>(_ json: String, as type: Payload.Type) throws -> Payload {
        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8) else {
            throw NSError(domain: "MemorizedTransactionCodec", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read memorized transaction payload."])
        }
        return try decoder.decode(Payload.self, from: data)
    }
}

struct SaveMemorizedTransactionSheet<Payload: Encodable>: View {
    @EnvironmentObject private var model: AppViewModel
    let type: MemorizedTransactionType
    let defaultName: String
    let payloadProvider: () -> Payload?
    var onSaved: (() -> Void)? = nil

    @State private var name = ""
    @State private var reminderFrequency: MemorizedReminderFrequency = .none
    @State private var nextDueDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memorize \(type.title)")
                        .font(.title2.bold())
                    Text("Save the current setup as a reusable template.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Template Name") {
                    TextField("Template name", text: $name)
                }

                Section("Reminder") {
                    Picker("Frequency", selection: $reminderFrequency) {
                        ForEach(MemorizedReminderFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }

                    if reminderFrequency != .none {
                        DatePicker("Next review date", selection: $nextDueDate, displayedComponents: .date)
                        Text("This only surfaces the template as due soon. It never creates an accounting entry automatically.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }

                Section("Notes") {
                    TextField("Optional reminder note", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.bad)
                            .font(.caption)
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
                Button("Save Template") { saveTemplate() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
        .onAppear {
            if name.isEmpty {
                name = defaultName
            }
        }
    }

    private func saveTemplate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a template name."
            return
        }
        guard let payload = payloadProvider() else {
            errorMessage = "This form needs a little more information before it can be memorized."
            return
        }

        do {
            let payloadJSON = try MemorizedTransactionCodec.encode(payload)
            _ = try model.db.saveMemorizedTransaction(
                name: trimmedName,
                type: type,
                payloadJSON: payloadJSON,
                reminderFrequency: reminderFrequency,
                nextDueDate: DateFormatter.isoDate.string(from: nextDueDate),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = "Could not save template: \(error.localizedDescription)"
        }
    }
}

struct MemorizedTransactionPickerSheet<Payload: Decodable>: View {
    @EnvironmentObject private var model: AppViewModel
    let type: MemorizedTransactionType
    let payloadType: Payload.Type
    let onApply: (Payload) -> Void

    @State private var templates: [MemorizedTransactionRow] = []
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use \(type.title)")
                        .font(.title2.bold())
                    Text("Choose a memorized template to apply to this form.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
            }
            .padding()

            Divider()

            if templates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.ink3)
                    Text("No memorized \(type.rawValue) templates yet.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(templates) { template in
                        templateRow(template)
                    }
                }
                .listStyle(.inset)
            }

            if !errorMessage.isEmpty {
                Divider()
                Text(errorMessage)
                    .foregroundStyle(AppTheme.bad)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
        }
        .frame(width: 520, height: 360)
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            templates = try model.db.fetchMemorizedTransactions(type: type)
        } catch {
            errorMessage = "Could not load templates: \(error.localizedDescription)"
        }
    }

    private func templateRow(_ template: MemorizedTransactionRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.headline)
                    reminderBadge(for: template)
                }

                Text(template.reminderStatusText)
                    .font(.caption)
                    .foregroundStyle(template.isDueSoon ? AppTheme.accent : AppTheme.ink3)

                if !template.notes.isEmpty {
                    Text(template.notes)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .lineLimit(2)
                }

                Text("Updated \(template.updatedAt.isEmpty ? "recently" : template.updatedAt)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            Spacer()

            Button("Delete") { deleteTemplate(template) }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.bad)

            Button("Use") { applyTemplate(template) }
                .buttonStyle(.renaissancePrimary)
        }
        .padding(.vertical, 4)
    }

    private func reminderBadge(for template: MemorizedTransactionRow) -> some View {
        Text(template.reminderFrequency.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(template.isDueSoon ? AppTheme.onPrimary : AppTheme.bodyText)
            .background(template.isDueSoon ? AppTheme.accent : AppTheme.panel)
            .clipShape(Capsule())
    }

    private func applyTemplate(_ template: MemorizedTransactionRow) {
        do {
            let payload = try MemorizedTransactionCodec.decode(template.payloadJSON, as: payloadType)
            onApply(payload)
            try model.db.recordMemorizedTransactionUse(
                id: template.id,
                nextDueDate: nextDueDateAfterUse(for: template)
            )
            dismiss()
        } catch {
            errorMessage = "Could not apply template: \(error.localizedDescription)"
        }
    }

    private func nextDueDateAfterUse(for template: MemorizedTransactionRow) -> String {
        guard let intervalDays = template.reminderFrequency.intervalDays,
              let date = Calendar.current.date(byAdding: .day, value: intervalDays, to: Date()) else {
            return template.reminderFrequency == .once ? "" : template.nextDueDate
        }
        return DateFormatter.isoDate.string(from: date)
    }

    private func deleteTemplate(_ template: MemorizedTransactionRow) {
        do {
            try model.db.deleteMemorizedTransaction(id: template.id)
            templates.removeAll { $0.id == template.id }
        } catch {
            errorMessage = "Could not delete template: \(error.localizedDescription)"
        }
    }
}
