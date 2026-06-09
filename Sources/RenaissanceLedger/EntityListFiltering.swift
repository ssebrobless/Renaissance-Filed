import Foundation

enum EntityListSortMode: String, CaseIterable, Identifiable {
    case alphabeticalAsc
    case alphabeticalDesc
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabeticalAsc:
            return "A-Z"
        case .alphabeticalDesc:
            return "Z-A"
        case .newest:
            return "Newest"
        case .oldest:
            return "Oldest"
        }
    }
}

enum EntityDateFilterMode: String, CaseIterable, Identifiable {
    case allTime
    case thisMonth
    case thisYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime:
            return "All Dates"
        case .thisMonth:
            return "This Month"
        case .thisYear:
            return "This Year"
        case .custom:
            return "Custom"
        }
    }
}

let entityInitialOptions: [String] = ["All", "#"] + (65...90).compactMap { UnicodeScalar($0).map(String.init) }

func entityInitialBucket(for value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let scalar = trimmed.unicodeScalars.first else { return "#" }
    let upper = CharacterSet.uppercaseLetters
    let lowercase = CharacterSet.lowercaseLetters
    if upper.contains(scalar) || lowercase.contains(scalar) {
        return String(scalar).uppercased()
    }
    return "#"
}

func entityDateMatches(
    createdAt: String,
    mode: EntityDateFilterMode,
    from customFrom: Date,
    to customTo: Date,
    calendar: Calendar = .current
) -> Bool {
    guard mode != .allTime else { return true }
    guard let date = entityDate(from: createdAt) else { return false }

    switch mode {
    case .allTime:
        return true
    case .thisMonth:
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? .distantFuture
        return date >= start && date <= end
    case .thisYear:
        let start = calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? .distantFuture
        return date >= start && date <= end
    case .custom:
        let start = min(customFrom.startOfDay(calendar: calendar), customTo.startOfDay(calendar: calendar))
        let end = max(customFrom.endOfDay(calendar: calendar), customTo.endOfDay(calendar: calendar))
        return date >= start && date <= end
    }
}

func sortEntityRows<T>(
    _ rows: [T],
    mode: EntityListSortMode,
    label: (T) -> String,
    createdAt: (T) -> String
) -> [T] {
    rows.sorted { lhs, rhs in
        let lhsLabel = label(lhs)
        let rhsLabel = label(rhs)
        switch mode {
        case .alphabeticalAsc:
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        case .alphabeticalDesc:
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedDescending
        case .newest, .oldest:
            let lhsDate = normalizedEntityDate(createdAt(lhs))
            let rhsDate = normalizedEntityDate(createdAt(rhs))
            let lhsHasDate = !lhsDate.isEmpty
            let rhsHasDate = !rhsDate.isEmpty

            if lhsHasDate != rhsHasDate {
                return lhsHasDate && !rhsHasDate
            }
            if lhsDate != rhsDate {
                if mode == .newest {
                    return lhsDate > rhsDate
                }
                return lhsDate < rhsDate
            }
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }
    }
}

private func normalizedEntityDate(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")
}

private func entityDate(from value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: trimmed) {
        return date
    }

    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: trimmed) {
        return date
    }

    let dateTimeFormatter = DateFormatter()
    dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    if let date = dateTimeFormatter.date(from: trimmed) {
        return date
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.date(from: trimmed)
}

private extension Date {
    func startOfDay(calendar: Calendar) -> Date {
        calendar.startOfDay(for: self)
    }

    func endOfDay(calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: self)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? self
    }
}
