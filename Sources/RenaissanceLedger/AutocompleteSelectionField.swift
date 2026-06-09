import SwiftUI

struct AutocompleteOption: Identifiable, Hashable {
    let id: Int64
    let title: String
    let subtitle: String
    let completionText: String

    init(id: Int64, title: String, subtitle: String = "", completionText: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.completionText = completionText ?? title
    }

    var displayText: String {
        subtitle.isEmpty ? title : "\(title) - \(subtitle)"
    }
}

struct AutocompleteSelectionField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var selectedID: Int64
    let options: [AutocompleteOption]
    var allowsCustomValue = false
    var maxSuggestions = 8
    var accessibilityID: String? = nil
    var onSelection: ((AutocompleteOption) -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var keepSuggestionsVisible = false

    private var normalizedQuery: String {
        normalizeAutocompleteToken(text)
    }

    private var matches: [AutocompleteOption] {
        let query = normalizedQuery
        let ranked = options.compactMap { option -> (rank: Int, option: AutocompleteOption)? in
            if query.isEmpty {
                return (3, option)
            }

            let title = normalizeAutocompleteToken(option.title)
            let subtitle = normalizeAutocompleteToken(option.subtitle)
            let completion = normalizeAutocompleteToken(option.completionText)
            let combined = normalizeAutocompleteToken(option.displayText)

            if title == query || completion == query || combined == query {
                return (0, option)
            }
            if title.hasPrefix(query) || completion.hasPrefix(query) {
                return (1, option)
            }
            if combined.contains(query) || subtitle.contains(query) {
                return (2, option)
            }
            return nil
        }

        return ranked
            .sorted {
                if $0.rank != $1.rank {
                    return $0.rank < $1.rank
                }
                if $0.option.title.count != $1.option.title.count {
                    return $0.option.title.count < $1.option.title.count
                }
                return $0.option.displayText.localizedCaseInsensitiveCompare($1.option.displayText) == .orderedAscending
            }
            .map(\.option)
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private var shouldShowSuggestions: Bool {
        (isFocused || keepSuggestionsVisible) && !matches.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)
                .focused($isFocused)
                .accessibilityIdentifier(accessibilityID ?? placeholder)
                .onTapGesture { keepSuggestionsVisible = true }
                .onChange(of: text) { newValue in
                    syncSelection(with: newValue)
                    keepSuggestionsVisible = true
                }
                .onSubmit {
                    if let exact = exactMatch(for: text) {
                        applySelection(exact)
                    } else if !allowsCustomValue, let first = matches.first {
                        applySelection(first)
                    }
                    keepSuggestionsVisible = false
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        finalizeEditing()
                    } else {
                        keepSuggestionsVisible = true
                    }
                }

            if shouldShowSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches) { option in
                        Button {
                            applySelection(option)
                            isFocused = false
                            keepSuggestionsVisible = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .foregroundStyle(AppTheme.bodyText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !option.subtitle.isEmpty {
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option.id != (matches.last?.id ?? -1) {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
                .zIndex(1)
            }
        }
    }

    private func syncSelection(with rawValue: String) {
        if rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !allowsCustomValue {
                selectedID = 0
            }
            return
        }

        if let exact = exactMatch(for: rawValue) {
            selectedID = exact.id
        } else if !allowsCustomValue {
            selectedID = 0
        }
    }

    private func finalizeEditing() {
        defer { keepSuggestionsVisible = false }

        if let exact = exactMatch(for: text) {
            applySelection(exact)
            return
        }

        if !allowsCustomValue {
            if let first = matches.first {
                applySelection(first)
            } else {
                selectedID = 0
                text = ""
            }
        }
    }

    private func exactMatch(for rawValue: String) -> AutocompleteOption? {
        let query = normalizeAutocompleteToken(rawValue)
        guard !query.isEmpty else { return nil }
        return options.first {
            let title = normalizeAutocompleteToken($0.title)
            let completion = normalizeAutocompleteToken($0.completionText)
            let combined = normalizeAutocompleteToken($0.displayText)
            return query == title || query == completion || query == combined
        }
    }

    private func applySelection(_ option: AutocompleteOption) {
        selectedID = option.id
        text = option.completionText
        onSelection?(option)
    }
}

private func normalizeAutocompleteToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}
