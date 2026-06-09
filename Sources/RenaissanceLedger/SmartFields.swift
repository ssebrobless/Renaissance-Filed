import AppKit
import SwiftUI

// MARK: - Date letter shortcuts (QuickBooks Desktop convention)
//
// In any date field a single-character keystroke jumps the date:
//   T = today
//   + / =        next day
//   - / _        previous day
//   M / m        first day of current month
//   H / h        last day of current month
//   Y / y        first day of current year
//   R / r        last day of current year
//   W / w        first day of current week
//   K / k        last day of current week
//   [ / {        same day previous week
//   ] / }        same day next week
//   ; / :        same day previous month
//   ' / "        same day next month

enum SmartDateShortcut {
    static func apply(char: Character, to current: Date) -> Date? {
        let cal = Calendar.current
        switch char {
        case "T", "t":
            return cal.startOfDay(for: Date())
        case "+", "=":
            return cal.date(byAdding: .day, value: 1, to: current)
        case "-", "_":
            return cal.date(byAdding: .day, value: -1, to: current)
        case "M", "m":
            return cal.date(from: cal.dateComponents([.year, .month], from: current))
        case "H", "h":
            guard let som = cal.date(from: cal.dateComponents([.year, .month], from: current)),
                  let nextMonth = cal.date(byAdding: .month, value: 1, to: som) else { return nil }
            return cal.date(byAdding: .day, value: -1, to: nextMonth)
        case "Y", "y":
            return cal.date(from: cal.dateComponents([.year], from: current))
        case "R", "r":
            guard let soy = cal.date(from: cal.dateComponents([.year], from: current)),
                  let nextYear = cal.date(byAdding: .year, value: 1, to: soy) else { return nil }
            return cal.date(byAdding: .day, value: -1, to: nextYear)
        case "W", "w":
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: current))
        case "K", "k":
            guard let sow = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: current)) else { return nil }
            return cal.date(byAdding: .day, value: 6, to: sow)
        case "[", "{":
            return cal.date(byAdding: .weekOfYear, value: -1, to: current)
        case "]", "}":
            return cal.date(byAdding: .weekOfYear, value: 1, to: current)
        case ";", ":":
            return cal.date(byAdding: .month, value: -1, to: current)
        case "'", "\"":
            return cal.date(byAdding: .month, value: 1, to: current)
        default:
            return nil
        }
    }

    static func parse(_ raw: String, anchor: Date = Date()) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.count == 1, let c = trimmed.first,
           let d = apply(char: c, to: anchor) {
            return d
        }
        let formats = ["MM/dd/yy", "MM/dd/yyyy", "M/d/yy", "M/d/yyyy",
                       "yyyy-MM-dd", "MM-dd-yy", "MM-dd-yyyy"]
        for fmt in formats {
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

private enum SmartDateFormatter {
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func string(from date: Date) -> String { display.string(from: date) }
}

// A text-first date field with QB letter shortcuts.
// Visually a small text box plus a calendar disclosure that opens the standard graphical picker.
@MainActor
struct SmartDateField: View {
    @Binding var date: Date
    var placeholder: String = "MM/DD/YY"
    @State private var showPicker: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            DateInputBridge(date: $date, placeholder: placeholder)
                .frame(minWidth: 92, idealWidth: 110, maxWidth: 130)
            Button {
                showPicker.toggle()
            } label: {
                Image(systemName: "calendar")
                    .imageScale(.small)
                    .foregroundStyle(AppTheme.ink3)
            }
            .buttonStyle(.borderless)
            .help("Open calendar")
            .popover(isPresented: $showPicker) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(8)
                    .frame(width: 260)
            }
        }
    }
}

private struct DateInputBridge: NSViewRepresentable {
    @Binding var date: Date
    var placeholder: String

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DateInputBridge
        // Set when programmatic update should not trigger commit
        var suppressEdit = false

        init(_ parent: DateInputBridge) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard !suppressEdit, let field = obj.object as? NSTextField else { return }
            let str = field.stringValue
            // Single-character shortcut (handles select-all + type case)
            if str.count == 1, let c = str.first,
               let newDate = SmartDateShortcut.apply(char: c, to: parent.date) {
                parent.date = newDate
                let formatted = SmartDateFormatter.string(from: newDate)
                suppressEdit = true
                field.stringValue = formatted
                field.currentEditor()?.selectedRange = NSRange(location: formatted.count, length: 0)
                suppressEdit = false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            commit(from: field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            // Tab / Enter / Return all flow through controlTextDidEndEditing automatically.
            // Esc reverts to last saved.
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                if let field = control as? NSTextField {
                    suppressEdit = true
                    field.stringValue = SmartDateFormatter.string(from: parent.date)
                    suppressEdit = false
                }
                return true
            }
            return false
        }

        private func commit(from field: NSTextField) {
            let str = field.stringValue
            if let parsed = SmartDateShortcut.parse(str, anchor: parent.date) {
                parent.date = parsed
                let formatted = SmartDateFormatter.string(from: parsed)
                suppressEdit = true
                field.stringValue = formatted
                suppressEdit = false
            } else {
                // Restore last good
                suppressEdit = true
                field.stringValue = SmartDateFormatter.string(from: parent.date)
                suppressEdit = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.usesSingleLineMode = true
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.stringValue = SmartDateFormatter.string(from: date)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let formatted = SmartDateFormatter.string(from: date)
        if nsView.stringValue != formatted, !context.coordinator.suppressEdit {
            // Avoid stomping on user mid-edit
            if nsView.currentEditor() == nil {
                context.coordinator.suppressEdit = true
                nsView.stringValue = formatted
                context.coordinator.suppressEdit = false
            }
        }
    }
}

// MARK: - Save split button (Save & Close primary, Save & New menu)
//
// In edit mode shows a simple "Save Changes" button.
// In new-record mode shows "Save & Close" + a dropdown with "Save & New".

@MainActor
struct SaveSplitButton: View {
    var isEditing: Bool
    var canSave: Bool
    var onSaveAndClose: () -> Void
    var onSaveAndNew: (() -> Void)?

    var body: some View {
        if isEditing {
            Button("Save Changes") { onSaveAndClose() }
                .buttonStyle(.renaissancePrimary)
                .disabled(!canSave)
        } else if let onSaveAndNew = onSaveAndNew {
            HStack(spacing: 0) {
                Button("Save & Close") { onSaveAndClose() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(!canSave)

                Menu {
                    Button("Save & New") { onSaveAndNew() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.buttonPrimaryText)
                        .frame(width: 18)
                        .frame(minHeight: 28)
                        .background(AppTheme.buttonPrimaryFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(AppTheme.accent2.opacity(0.60), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .disabled(!canSave)
            }
        } else {
            Button("Save & Close") { onSaveAndClose() }
                .buttonStyle(.renaissancePrimary)
                .disabled(!canSave)
        }
    }
}

// MARK: - Inline-math numeric field
//
// Accepts arithmetic on commit (Tab / Enter / blur):
//   "150*1.07"   -> 160.50
//   "12+8"       -> 20
//   "(40-3)*5"   -> 185
// Strips "$" and "," before parsing. Restores last good value if the
// expression is ill-formed.

enum InlineMath {
    private static let allowed = CharacterSet(charactersIn: "0123456789+-*/.() ")

    static func evaluate(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return nil }
        if let d = Double(cleaned) { return d }
        if cleaned.unicodeScalars.contains(where: { !allowed.contains($0) }) { return nil }
        var parser = ShuntingParser(input: cleaned)
        let result = parser.parseExpression()
        return parser.atEnd ? result : nil
    }
}

private struct ShuntingParser {
    let chars: [Character]
    var pos: Int = 0

    init(input: String) { self.chars = Array(input) }

    var atEnd: Bool {
        var p = pos
        while p < chars.count, chars[p] == " " { p += 1 }
        return p == chars.count
    }

    mutating func peek() -> Character? {
        while pos < chars.count, chars[pos] == " " { pos += 1 }
        return pos < chars.count ? chars[pos] : nil
    }

    @discardableResult
    mutating func advance() -> Character? {
        let c = peek()
        if c != nil { pos += 1 }
        return c
    }

    mutating func parseExpression() -> Double? {
        guard var lhs = parseTerm() else { return nil }
        while let c = peek(), c == "+" || c == "-" {
            _ = advance()
            guard let rhs = parseTerm() else { return nil }
            lhs = (c == "+") ? lhs + rhs : lhs - rhs
        }
        return lhs
    }

    mutating func parseTerm() -> Double? {
        guard var lhs = parseFactor() else { return nil }
        while let c = peek(), c == "*" || c == "/" {
            _ = advance()
            guard let rhs = parseFactor() else { return nil }
            if c == "/" {
                if rhs == 0 { return nil }
                lhs = lhs / rhs
            } else {
                lhs = lhs * rhs
            }
        }
        return lhs
    }

    mutating func parseFactor() -> Double? {
        guard let c = peek() else { return nil }
        if c == "(" {
            _ = advance()
            guard let inner = parseExpression() else { return nil }
            guard peek() == ")" else { return nil }
            _ = advance()
            return inner
        }
        if c == "-" {
            _ = advance()
            guard let f = parseFactor() else { return nil }
            return -f
        }
        if c == "+" {
            _ = advance()
            return parseFactor()
        }
        return parseNumber()
    }

    mutating func parseNumber() -> Double? {
        var s = ""
        var sawDot = false
        while let c = peek() {
            if c.isNumber {
                s.append(c)
                _ = advance()
            } else if c == "." && !sawDot {
                sawDot = true
                s.append(c)
                _ = advance()
            } else { break }
        }
        return s.isEmpty ? nil : Double(s)
    }
}

// Drop-in TextField wrapper for existing String-bound numeric fields.
// Preserves the form's `text: $amount` contract: on commit (Tab / Enter / blur)
// inline math is evaluated and the formatted numeric string is written back.
// Unparseable input is left untouched so the form's existing Double parser
// surfaces the same error path it does today (no behavior regression on save).
@MainActor
struct CalcStringField: View {
    @Binding var text: String
    var placeholder: String = "0.00"
    var decimals: Int = 2
    var allowsNegative: Bool = true

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .foregroundStyle(.black)
            .focused($focused)
            .onChange(of: focused) { isFocused in
                if !isFocused { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return }
        guard let d = InlineMath.evaluate(trimmed) else { return }
        let signed = allowsNegative ? d : max(0, d)
        text = format(signed)
    }

    private func format(_ d: Double) -> String {
        if d == d.rounded() {
            return String(Int(d))
        }
        return String(format: "%.\(decimals)f", d)
    }
}

// SwiftUI numeric field that evaluates inline math on commit.
// `decimals` controls display precision; raw editing shows the underlying double without grouping.
@MainActor
struct CalcField: View {
    @Binding var value: Double
    var placeholder: String = "0.00"
    var decimals: Int = 2
    var allowsNegative: Bool = true
    var alignment: TextAlignment = .trailing

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .foregroundStyle(.black)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onAppear { text = formatted(value) }
            .onChange(of: value) { new in
                if !focused { text = formatted(new) }
            }
            .onChange(of: focused) { isFocused in
                if isFocused {
                    text = editableString(for: value)
                    DispatchQueue.main.async {
                        if let editor = NSApp.keyWindow?.firstResponder as? NSText {
                            editor.selectAll(nil)
                        }
                    }
                } else {
                    commit()
                }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        if let d = InlineMath.evaluate(text) {
            let signed = allowsNegative ? d : max(0, d)
            value = signed
            text = formatted(signed)
        } else {
            text = formatted(value)
        }
    }

    private func formatted(_ d: Double) -> String {
        String(format: "%.\(decimals)f", d)
    }

    private func editableString(for d: Double) -> String {
        if d == 0 { return "" }
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%g", d)
    }
}
