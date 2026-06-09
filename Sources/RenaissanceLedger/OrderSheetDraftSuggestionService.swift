import Foundation

enum OrderSheetDraftSuggestionService {
    private enum DocumentKind {
        case general
        case selectionSheet
    }

    static func suggestDraft(
        ocrLines: [OrderSheetOCRLine],
        customers: [CustomerRow],
        serviceItems: [ServiceItemRow],
        companyName: String,
        referenceDate: Date = Date(),
        preferredStatus: String = "draft"
    ) -> OrderSheetReviewDraft? {
        let cleanedLines = ocrLines
            .map { line in
                OrderSheetOCRLine(
                    id: line.id,
                    text: cleanedText(line.text),
                    confidence: line.confidence,
                    minX: line.minX,
                    minY: line.minY,
                    width: line.width,
                    height: line.height
                )
            }
            .filter { !$0.text.isEmpty }

        guard !cleanedLines.isEmpty else { return nil }

        let rows = groupedRows(from: cleanedLines)
        let documentKind = detectedDocumentKind(from: rows)
        let issueDate = parsedOrderDate(from: rows) ?? referenceDate
        let validUntil = Calendar.current.date(byAdding: .day, value: 30, to: issueDate) ?? issueDate
        let suggestedLines = suggestedDraftLines(from: rows, serviceItems: serviceItems, documentKind: documentKind)
        let suggestedCustomerID = suggestedCustomerID(from: rows, customers: customers, companyName: companyName)
        let memo = suggestedMemo(from: rows)

        return OrderSheetReviewDraft(
            customerID: suggestedCustomerID,
            issueDate: DateFormatter.isoDate.string(from: issueDate),
            validUntil: DateFormatter.isoDate.string(from: validUntil),
            memo: memo,
            status: preferredStatus.isEmpty ? "draft" : preferredStatus,
            lines: suggestedLines.isEmpty ? [.blank()] : suggestedLines
        )
    }

    private struct OCRRow {
        let lines: [OrderSheetOCRLine]
        let baselineY: Double

        var text: String {
            lines
                .sorted { lhs, rhs in
                    if abs(lhs.minX - rhs.minX) > 0.002 {
                        return lhs.minX < rhs.minX
                    }
                    return lhs.text < rhs.text
                }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct NumericToken {
        let text: String
        let value: Double
        let minX: Double
    }

    private static func detectedDocumentKind(from rows: [OCRRow]) -> DocumentKind {
        let normalizedRows = rows.prefix(18).map { normalized($0.text) }
        return normalizedRows.contains { $0.contains("SELECTION SHEET") } ? .selectionSheet : .general
    }

    private static func groupedRows(from lines: [OrderSheetOCRLine]) -> [OCRRow] {
        let sorted = lines.sorted { lhs, rhs in
            if abs(lhs.minY - rhs.minY) > 0.012 {
                return lhs.minY > rhs.minY
            }
            return lhs.minX < rhs.minX
        }

        var groups: [[OrderSheetOCRLine]] = []
        var baselines: [Double] = []

        for line in sorted {
            if let lastBaseline = baselines.last, abs(lastBaseline - line.minY) <= 0.016 {
                groups[groups.count - 1].append(line)
                let existingCount = Double(groups[groups.count - 1].count)
                baselines[baselines.count - 1] = ((lastBaseline * (existingCount - 1)) + line.minY) / existingCount
            } else {
                groups.append([line])
                baselines.append(line.minY)
            }
        }

        return zip(groups, baselines).map { OCRRow(lines: $0.0, baselineY: $0.1) }
    }

    private static func parsedOrderDate(from rows: [OCRRow]) -> Date? {
        let labelRows = rows.filter { normalized($0.text).contains("ORDER DATE") || normalized($0.text).contains("QUOTE DATE") }
        for row in labelRows {
            if let date = firstDate(in: row.text) {
                return date
            }
        }

        for row in rows.prefix(12) {
            if let date = firstDate(in: row.text) {
                return date
            }
        }
        return nil
    }

    private static func suggestedMemo(from rows: [OCRRow]) -> String {
        var parts: [String] = []

        if let supplier = suggestedSupplier(from: rows),
           let orderNumber = extractedFieldValue(labels: ["ORDER NUMBER", "QUOTE NUMBER", "QUOTATION NUMBER"], rows: rows) {
            parts.append("\(supplier) quotation \(orderNumber)")
        } else if let orderNumber = extractedFieldValue(labels: ["ORDER NUMBER", "QUOTE NUMBER", "QUOTATION NUMBER"], rows: rows) {
            parts.append("Quotation \(orderNumber)")
        } else if let supplier = suggestedSupplier(from: rows) {
            parts.append(supplier)
        }

        if let project = extractedFieldValue(labels: ["PO NUMBER", "PROJECT", "JOB NAME", "REFERENCE"], rows: rows),
           !project.isEmpty {
            parts.append("Project / PO: \(project)")
        }

        return parts.joined(separator: "\n")
    }

    private static func suggestedSupplier(from rows: [OCRRow]) -> String? {
        let excludedPhrases = [
            "QUOTATION", "BILL TO", "SHIP TO", "ORDER NUMBER", "ORDER DATE",
            "PO NUMBER", "PAGE", "PHONE", "FAX", "TERMS"
        ]

        for row in rows.prefix(8) {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = normalized(text)
            guard !text.isEmpty else { continue }
            guard !excludedPhrases.contains(where: { upper.contains($0) }) else { continue }
            guard !looksLikeAddressOrPhone(text) else { continue }
            guard !containsDate(text) else { continue }
            let wordCount = text.split(separator: " ").count
            guard wordCount <= 6 else { continue }
            if text.rangeOfCharacter(from: .letters) != nil {
                return text
            }
        }
        return nil
    }

    private static func suggestedCustomerID(from rows: [OCRRow], customers: [CustomerRow], companyName: String) -> Int64? {
        var candidateTexts: [String] = []

        if let billTo = extractedBlock(afterLabel: "BILL TO", rows: rows) {
            candidateTexts.append(contentsOf: billTo)
        }
        if let shipTo = extractedBlock(afterLabel: "SHIP TO", rows: rows) {
            candidateTexts.append(contentsOf: shipTo)
        }
        if let customer = extractedFieldValue(labels: ["CUSTOMER", "HOMEOWNER"], rows: rows) {
            candidateTexts.append(customer)
        }

        let normalizedCompany = normalized(companyName)
        var bestMatch: (id: Int64, score: Double)?

        for candidate in candidateTexts {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalizedCandidate = normalized(trimmed)
            guard !normalizedCandidate.isEmpty else { continue }
            if !normalizedCompany.isEmpty, normalizedCandidate.contains(normalizedCompany) {
                continue
            }

            for customer in customers {
                let labels = [customer.displayLabel, customer.name, customer.company]
                    .map(normalized)
                    .filter { !$0.isEmpty }

                let score = labels.map { similarityScore(candidate: normalizedCandidate, target: $0) }.max() ?? 0
                guard score >= 0.94 else { continue }
                if let bestMatch, bestMatch.score >= score {
                    continue
                }
                bestMatch = (customer.id, score)
            }
        }

        return bestMatch?.id
    }

    private static func suggestedDraftLines(
        from rows: [OCRRow],
        serviceItems: [ServiceItemRow],
        documentKind: DocumentKind
    ) -> [OrderSheetDraftLine] {
        let blocks = itemBlocks(from: rows)
        let rawLines: [OrderSheetDraftLine] = blocks.compactMap { block -> OrderSheetDraftLine? in
            let lineTexts = block.flatMap(\.lines).map(\.text)
            let code = lineTexts.compactMap(extractedItemCode).first
            let numericTokens = block
                .flatMap(\.lines)
                .compactMap { line -> NumericToken? in
                    guard let value = parsedNumber(from: line.text) else { return nil }
                    return NumericToken(text: line.text, value: value, minX: line.minX)
                }

            let amountToken = numericTokens
                .filter { $0.minX >= 0.84 && decimalPrecision(of: $0.text) == 2 }
                .sorted { lhs, rhs in lhs.minX > rhs.minX }
                .first

            let rateToken = numericTokens
                .filter { token in
                    token.minX >= 0.74 && token.minX < 0.84 && token.text != amountToken?.text
                }
                .sorted { lhs, rhs in lhs.minX > rhs.minX }
                .first

            let quantityToken = numericTokens
                .filter { token in
                    token.minX < 0.14 &&
                    token.text != amountToken?.text &&
                    token.text != rateToken?.text
                }
                .filter { $0.value > 0 }
                .sorted { lhs, rhs in lhs.minX < rhs.minX }
                .first
                ?? numericTokens
                .filter { token in
                    token.minX >= 0.14 && token.minX < 0.30 &&
                    token.text != amountToken?.text &&
                    token.text != rateToken?.text &&
                    token.value > 0
                }
                .sorted { lhs, rhs in lhs.minX < rhs.minX }
                .first

            let quantityValue = quantityToken?.value ?? 1
            let amountValue = amountToken?.value
            let rateValue = rateToken?.value ?? ((amountValue ?? 0) > 0 ? (amountValue ?? 0) / max(quantityValue, 1) : 0)
            let resolvedAmount = amountValue ?? (quantityValue * rateValue)

            let descriptionPieces = dedupedDescriptionPieces(from: block, itemCode: code)
            let description = formattedDescription(from: descriptionPieces)
            let reviewHint = formattedReviewHint(
                from: block,
                itemCode: code,
                quantityToken: quantityToken,
                rateToken: rateToken,
                amountToken: amountToken,
                descriptionPieces: descriptionPieces,
                documentKind: documentKind
            )

            guard !description.isEmpty || resolvedAmount > 0 else { return nil }

            let matchedServiceItem = matchedServiceItem(
                description: description,
                itemCode: code,
                rate: rateValue,
                serviceItems: serviceItems
            )

            return OrderSheetDraftLine(
                selectedItemID: matchedServiceItem?.id ?? 0,
                itemName: matchedServiceItem?.name ?? (code ?? ""),
                description: description.isEmpty ? (matchedServiceItem?.description.isEmpty == false ? matchedServiceItem?.description ?? "" : (matchedServiceItem?.name ?? code ?? "")) : description,
                quantity: formattedQuantity(quantityValue),
                rate: formattedMoney(rateValue),
                reviewHint: reviewHint
            )
        }
        return mergedDraftLines(rawLines)
    }

    private static func itemBlocks(from rows: [OCRRow]) -> [[OCRRow]] {
        var blocks: [[OCRRow]] = []
        var current: [OCRRow] = []
        var encounteredItems = false
        var inItemRegion = false

        for row in rows {
            let text = row.text
            if !inItemRegion {
                let upper = normalized(text)
                if upper.contains("QUANTITIES")
                    || upper.contains("ITEM DESCRIPTION")
                    || upper.contains("UNIT SIZE")
                    || upper.contains("PRICING") {
                    inItemRegion = true
                }
                continue
            }

            if isFooterRow(text) {
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
                if encounteredItems {
                    break
                }
                continue
            }

            if isLikelyItemStart(row) {
                if !current.isEmpty {
                    blocks.append(current)
                }
                current = [row]
                encounteredItems = true
                continue
            }

            guard !current.isEmpty else { continue }

            if isLikelySectionBreak(text) {
                blocks.append(current)
                current = []
                continue
            }

            current.append(row)
        }

        if !current.isEmpty {
            blocks.append(current)
        }

        return blocks
    }

    private static func isLikelyItemStart(_ row: OCRRow) -> Bool {
        let texts = row.lines.map(\.text)
        if texts.contains(where: isLikelyItemCode) {
            return true
        }
        if texts.contains(where: isLikelyItemMarker) {
            return true
        }

        let hasAmountishNumber = row.lines.contains { line in
            guard let value = parsedNumber(from: line.text) else { return false }
            return line.minX > 0.70 && value > 0
        }
        let hasDescriptionishText = texts.contains { text in
            text.rangeOfCharacter(from: .letters) != nil &&
            !isLikelyHeader(text) &&
            !looksLikeAddressOrPhone(text)
        }
        return hasAmountishNumber && hasDescriptionishText
    }

    private static func dedupedDescriptionPieces(from block: [OCRRow], itemCode: String?) -> [String] {
        var pieces: [String] = []

        for row in block {
            for line in row.lines {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                guard line.confidence >= 0.45 else { continue }
                guard text != itemCode else { continue }
                guard !isLikelyItemMarker(text) else { continue }
                guard !isLikelyHeader(text) else { continue }
                guard !isIgnoredInventoryNote(text) else { continue }
                guard !looksLikeStandaloneUnit(text) else { continue }
                guard parsedNumber(from: text) == nil else { continue }
                guard line.minX >= 0.33 && line.minX <= 0.76 else { continue }
                if let extractedCode = extractedItemCode(from: text),
                   extractedCode == itemCode,
                   text.split(separator: " ").count <= 3 {
                    continue
                }
                appendUnique(text, into: &pieces)
            }
        }

        return pieces
    }

    private static func formattedDescription(from pieces: [String]) -> String {
        let cleanedPieces = pieces
            .map { piece in
                piece
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: " ,", with: ",")
                    .replacingOccurrences(of: " .", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard !cleanedPieces.isEmpty else { return "" }

        var merged: [String] = []
        for piece in cleanedPieces {
            if var last = merged.last, shouldJoinDescriptionContinuation(previous: last, next: piece) {
                last += " " + piece
                merged[merged.count - 1] = last
            } else {
                merged.append(piece)
            }
        }

        guard let first = merged.first else { return "" }
        if merged.count == 1 {
            return first
        }
        if first.hasPrefix("For ") || first.hasPrefix("[") {
            return merged.joined(separator: " ")
        }
        return first + " - " + merged.dropFirst().joined(separator: "; ")
    }

    private static func matchedServiceItem(
        description: String,
        itemCode: String?,
        rate: Double,
        serviceItems: [ServiceItemRow]
    ) -> ServiceItemRow? {
        let searchableText = normalized([itemCode, description].compactMap { $0 }.joined(separator: " "))
        guard !searchableText.isEmpty else { return nil }

        var bestMatch: (item: ServiceItemRow, score: Double)?
        for item in serviceItems {
            let nameScore = similarityScore(candidate: searchableText, target: normalized(item.name))
            let descriptionScore = similarityScore(candidate: searchableText, target: normalized(item.description))
            var score = max(nameScore, descriptionScore)

            if rate > 0, item.unitPrice > 0 {
                let delta = abs(item.unitPrice - rate)
                if delta <= 0.05 {
                    score += 0.08
                } else if delta <= max(rate * 0.05, 0.25) {
                    score += 0.04
                }
            }

            guard score >= 0.97 else { continue }
            if let bestMatch, bestMatch.score >= score {
                continue
            }
            bestMatch = (item, score)
        }
        return bestMatch?.item
    }

    private static func extractedBlock(afterLabel label: String, rows: [OCRRow]) -> [String]? {
        let normalizedLabel = normalized(label)
        for (index, row) in rows.enumerated() {
            let rowText = normalized(row.text)
            guard rowText.contains(normalizedLabel) else { continue }

            var collected: [String] = []
            for nextIndex in (index + 1)..<min(rows.count, index + 5) {
                let text = rows[nextIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let upper = normalized(text)
                if isLikelyHeader(text) || upper.contains("PO NUMBER") || upper.contains("ORDER NUMBER") || upper.contains("ORDER DATE") {
                    break
                }
                if looksLikeAddressOrPhone(text) {
                    continue
                }
                collected.append(text)
            }
            if !collected.isEmpty {
                return collected
            }
        }
        return nil
    }

    private static func extractedFieldValue(labels: [String], rows: [OCRRow]) -> String? {
        for label in labels {
            let normalizedLabel = normalized(label)
            for (index, row) in rows.enumerated() {
                let rowText = row.text
                let upper = normalized(rowText)
                guard upper.contains(normalizedLabel) else { continue }

                if let labelLine = row.lines.first(where: { normalized($0.text).contains(normalizedLabel) }) {
                    let leftBound = max(0, labelLine.minX - 0.05)
                    let rightBound = labelLine.minX > 0.55
                        ? 1.0
                        : min(1.0, labelLine.minX + max(labelLine.width * 2.0, 0.22))

                    for nextIndex in (index + 1)..<min(rows.count, index + 3) {
                        let candidateParts = rows[nextIndex].lines
                            .filter { $0.minX >= leftBound && $0.minX <= rightBound }
                            .map(\.text)
                        let candidate = candidateParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !candidate.isEmpty else { continue }
                        if isLikelyHeader(candidate) {
                            break
                        }
                        return candidate
                    }

                    let sameRowTrailing = row.lines
                        .filter { $0.minX > (labelLine.minX + labelLine.width + 0.01) }
                        .map(\.text)
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sameRowTrailing.isEmpty {
                        return sameRowTrailing
                    }
                }

                if let trailing = trailingValue(after: label, in: rowText), !trailing.isEmpty {
                    return trailing
                }

                for nextIndex in (index + 1)..<min(rows.count, index + 3) {
                    let candidate = rows[nextIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !candidate.isEmpty else { continue }
                    if isLikelyHeader(candidate) {
                        break
                    }
                    return candidate
                }
            }
        }
        return nil
    }

    private static func trailingValue(after label: String, in text: String) -> String? {
        let lowercased = text.lowercased()
        let labelLowercased = label.lowercased()
        guard let range = lowercased.range(of: labelLowercased) else { return nil }
        let trailing = text[range.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: ": -\t").union(.whitespacesAndNewlines))
        return trailing.isEmpty ? nil : String(trailing)
    }

    private static func firstDate(in text: String) -> Date? {
        let pattern = #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range, in: text)
        else {
            return nil
        }

        let candidate = String(text[range])
        let formatters = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy"].map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
        return formatters.compactMap { $0.date(from: candidate) }.first
    }

    private static func similarityScore(candidate: String, target: String) -> Double {
        guard !candidate.isEmpty, !target.isEmpty else { return 0 }
        if candidate == target {
            return 1
        }
        if candidate.contains(target) || target.contains(candidate) {
            return Double(min(candidate.count, target.count)) / Double(max(candidate.count, target.count))
        }

        let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
        let targetTokens = Set(target.split(separator: " ").map(String.init))
        guard !candidateTokens.isEmpty, !targetTokens.isEmpty else { return 0 }
        let intersection = candidateTokens.intersection(targetTokens).count
        let union = candidateTokens.union(targetTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func cleanedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{fb01}", with: "fi")
            .replacingOccurrences(of: "\u{fb02}", with: "fl")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        cleanedText(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func parsedNumber(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNumeric = trimmed
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanedNumeric.range(of: #"^\$?-?\d+(?:,\d{3})*(?:\.\d+)?$"#, options: .regularExpression) != nil else {
            return nil
        }
        guard !looksLikeAddressOrPhone(cleanedNumeric) else { return nil }

        let stripped = cleanedNumeric
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(stripped)
    }

    private static func decimalPrecision(of text: String) -> Int {
        guard let decimalIndex = text.firstIndex(of: ".") else { return 0 }
        return text.distance(from: text.index(after: decimalIndex), to: text.endIndex)
    }

    private static func formattedQuantity(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }

        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.minimumIntegerDigits = 1
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    private static func formattedMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        formatter.minimumIntegerDigits = 1
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func appendUnique(_ text: String, into array: inout [String]) {
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return }
        guard !array.contains(where: { normalized($0) == normalizedText }) else { return }
        array.append(text)
    }

    private static func shouldJoinDescriptionContinuation(previous: String, next: String) -> Bool {
        guard let first = next.first else { return false }
        if first.isLowercase {
            return true
        }
        if previous.hasSuffix(",") || previous.hasSuffix("/") || previous.hasSuffix("-") {
            return true
        }
        if next.hasPrefix("[") {
            return true
        }
        return false
    }

    private static func mergedDraftLines(_ lines: [OrderSheetDraftLine]) -> [OrderSheetDraftLine] {
        var merged: [OrderSheetDraftLine] = []

        for line in lines {
            if var previous = merged.last, shouldMerge(previous: previous, next: line) {
                let mergedDescription = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !mergedDescription.isEmpty {
                    previous.description = mergedDescription
                }
                let mergedHint = [previous.reviewHint, line.reviewHint]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                previous.reviewHint = mergedHint
                if previous.selectedItemID == 0, line.selectedItemID != 0 {
                    previous.selectedItemID = line.selectedItemID
                }
                if previous.itemName.isEmpty {
                    previous.itemName = line.itemName
                }
                merged[merged.count - 1] = previous
                continue
            }

            merged.append(line)
        }

        return merged.filter { !isLikelyMetadataNoise($0) }
    }

    private static func shouldMerge(previous: OrderSheetDraftLine, next: OrderSheetDraftLine) -> Bool {
        let previousDescription = normalized(previous.description)
        let nextDescription = normalized(next.description)
        let previousRate = Double(previous.rate) ?? 0
        let nextRate = Double(next.rate) ?? 0

        guard previousRate > 0, nextRate == 0 else { return false }
        guard !nextDescription.isEmpty else { return false }
        return previousDescription == normalized(previous.itemName)
            || extractedItemCode(from: previous.description) != nil
    }

    private static func isLikelyMetadataNoise(_ line: OrderSheetDraftLine) -> Bool {
        let description = normalized(line.description)
        // Generic header/footer text to ignore when parsing scanned order sheets.
        // Add your own supplier's letterhead phrases here per deployment.
        let noiseMarkers = [
            "VISIT US", "ORDER NUMBER", "SHIP ROUTE", "QUOTATION"
        ]
        return noiseMarkers.contains { description.contains($0) }
    }

    private static func isLikelyItemMarker(_ text: String) -> Bool {
        text.range(of: #"^\(?\d{3}\)?$"#, options: .regularExpression) != nil
    }

    private static func isLikelyItemCode(_ text: String) -> Bool {
        extractedItemCode(from: text) != nil && !isLikelyHeader(text)
    }

    private static func isLikelyHeader(_ text: String) -> Bool {
        let upper = normalized(text)
        let headers = [
            "QUOTATION", "BILL TO", "SHIP TO", "ORDER NUMBER", "ORDER DATE", "PAGE",
            "PO NUMBER", "QTY", "QUANTITY", "UNIT PRICE", "PRICE", "AMOUNT", "TOTAL",
            "SUBTOTAL", "TERMS", "SALESPERSON", "PHONE", "FAX", "CUSTOMER"
        ]
        return headers.contains { upper.contains($0) }
    }

    private static func isFooterRow(_ text: String) -> Bool {
        let upper = normalized(text)
        return upper.contains("SUBTOTAL") || upper.contains("TOTAL") || upper.contains("BALANCE")
    }

    private static func isLikelySectionBreak(_ text: String) -> Bool {
        let upper = normalized(text)
        return upper.contains("THANK YOU") || upper.contains("REMIT") || upper.contains("PAYMENT")
    }

    private static func formattedReviewHint(
        from block: [OCRRow],
        itemCode: String?,
        quantityToken: NumericToken?,
        rateToken: NumericToken?,
        amountToken: NumericToken?,
        descriptionPieces: [String],
        documentKind: DocumentKind
    ) -> String {
        guard documentKind == .selectionSheet else { return "" }

        let descriptionSet = Set(descriptionPieces.map(normalized))
        let ignoredNumbers = Set(
            [quantityToken?.text, rateToken?.text, amountToken?.text]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        var hintParts: [String] = []

        for row in block {
            for line in row.lines {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let upper = normalized(text)
                guard !text.isEmpty else { continue }
                guard text != itemCode else { continue }
                guard !descriptionSet.contains(upper) else { continue }
                guard !isLikelyHeader(text) else { continue }
                guard !isIgnoredInventoryNote(text) else { continue }
                guard !looksLikeStandaloneUnit(text) else { continue }
                guard !isLikelyItemMarker(text) else { continue }
                guard !ignoredNumbers.contains(text) else { continue }

                if let parsed = parsedNumber(from: text),
                   line.minX <= 0.22,
                   abs(parsed - (quantityToken?.value ?? .nan)) > 0.001 {
                    appendUnique("Possible handwritten qty/order note: \(formattedQuantity(parsed))", into: &hintParts)
                    continue
                }

                if line.minX <= 0.26 {
                    if text.rangeOfCharacter(from: .letters) != nil {
                        appendUnique("Margin note: \(text)", into: &hintParts)
                    }
                    continue
                }

                let looksLikeFreeformNote =
                    text.rangeOfCharacter(from: .letters) != nil &&
                    (upper.contains("BOX") || upper.contains("NICHE") || upper.contains("GRAY") || upper.contains("GREY") || upper.contains("NORTH") || upper.contains("SOUTH") || upper.contains("EAST") || upper.contains("WEST") || text.contains("x"))

                if looksLikeFreeformNote {
                    appendUnique("Handwritten note: \(text)", into: &hintParts)
                }
            }
        }

        return hintParts.joined(separator: " | ")
    }

    private static func looksLikeStandaloneUnit(_ text: String) -> Bool {
        let upper = normalized(text)
        let units = ["EA", "SF", "LF", "SQFT", "SQ FT", "PCS", "CTN", "BOX", "GAL", "BAG"]
        return units.contains(upper)
    }

    private static func isIgnoredInventoryNote(_ text: String) -> Bool {
        let upper = normalized(text)
        let prefixes = [
            "CARTONS", "PIECES", "UNIT CONVERSION", "QTY", "ORDERED", "ALLOCATED",
            "REMAINING", "UNIT SIZE", "EXTENDED", "PRICE", "VOM"
        ]
        return prefixes.contains { upper.hasPrefix($0) }
    }

    private static func extractedItemCode(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Z0-9-]{5,}"#) else { return nil }
        let upper = cleanedText(text).uppercased()
        let nsRange = NSRange(upper.startIndex..<upper.endIndex, in: upper)
        let matches = regex.matches(in: upper, range: nsRange)
        let candidates = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: upper) else { return nil }
            let candidate = String(upper[range])
            let hasLetters = candidate.rangeOfCharacter(from: .letters) != nil
            let hasDigits = candidate.rangeOfCharacter(from: .decimalDigits) != nil
            return hasLetters && hasDigits ? candidate : nil
        }
        return candidates.max(by: { $0.count < $1.count })
    }

    private static func looksLikeAddressOrPhone(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.range(of: #"\b\d{3}[-)\s]\d{3}[-\s]\d{4}\b"#, options: .regularExpression) != nil {
            return true
        }
        if cleaned.range(of: #"\b\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil,
           cleaned.rangeOfCharacter(from: .letters) != nil {
            return true
        }
        if cleaned.range(of: #"^\d+\s+\w+"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func containsDate(_ text: String) -> Bool {
        firstDate(in: text) != nil
    }
}
