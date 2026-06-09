import Foundation

private struct EntityNamePresentation {
    let title: String
    let detail: String?
}

// Maps OCR-truncated imported names (ones that came in ending with an ellipsis)
// back to their full form. Populate per-deployment from your own imported data;
// empty by default so no business's customer list ships with the app.
private let importedEllipsisCanonicalRoots: [String: String] = [:]

func userFacingEntityName(_ raw: String) -> String {
    entityNamePresentation(raw).title
}

func userFacingEntityDetail(_ raw: String) -> String? {
    entityNamePresentation(raw).detail
}

func userFacingEntityLabel(_ raw: String) -> String {
    let presentation = entityNamePresentation(raw)
    guard let detail = presentation.detail, !detail.isEmpty else {
        return presentation.title
    }
    return "\(presentation.title) · \(detail)"
}

private func entityNamePresentation(_ raw: String) -> EntityNamePresentation {
    let cleaned = raw
        .replacingOccurrences(of: "\u{fb01}", with: "fi")
        .replacingOccurrences(of: "\u{fb02}", with: "fl")
        .replacingOccurrences(of: "\u{00a0}", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !cleaned.isEmpty else {
        return EntityNamePresentation(title: raw, detail: nil)
    }

    if let regex = try? NSRegularExpression(pattern: #"^(.*?)\s*\(Job\s+(\d+)\)$"#) {
        let nsRange = NSRange(cleaned.startIndex ..< cleaned.endIndex, in: cleaned)
        if let result = regex.firstMatch(in: cleaned, range: nsRange),
           let baseRange = Range(result.range(at: 1), in: cleaned),
           let numberRange = Range(result.range(at: 2), in: cleaned)
        {
            let base = cleaned[baseRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let number = cleaned[numberRange]
            if !base.isEmpty {
                return EntityNamePresentation(title: base, detail: "Job \(number)")
            }
        }
    }

    if let match = cleaned.range(of: #"^(.*?)(?:\s+)(\d+)$"#, options: .regularExpression) {
        let whole = String(cleaned[match])
        if let regex = try? NSRegularExpression(pattern: #"^(.*?)(?:\s+)(\d+)$"#) {
            let nsRange = NSRange(whole.startIndex ..< whole.endIndex, in: whole)
            if let result = regex.firstMatch(in: whole, range: nsRange),
               let baseRange = Range(result.range(at: 1), in: whole),
               let numberRange = Range(result.range(at: 2), in: whole)
            {
                let base = whole[baseRange].trimmingCharacters(in: .whitespacesAndNewlines)
                let number = whole[numberRange]
                if !base.isEmpty {
                    return EntityNamePresentation(title: base, detail: "Job \(number)")
                }
            }
        }
    }

    if cleaned.contains("...") {
        let root = cleaned
            .components(separatedBy: "...")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? cleaned
        let canonicalRoot = importedEllipsisCanonicalRoots[root] ?? root
        if !canonicalRoot.isEmpty {
            return EntityNamePresentation(title: canonicalRoot, detail: nil)
        }
    }

    return EntityNamePresentation(title: cleaned, detail: nil)
}
