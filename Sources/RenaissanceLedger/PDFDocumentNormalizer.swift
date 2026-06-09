import CoreGraphics
import Foundation

enum PDFDocumentNormalizerError: LocalizedError {
    case unreadableDocument(String)
    case failedCreatingOutput(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableDocument(path):
            return "Could not read PDF document at \(path)."
        case let .failedCreatingOutput(path):
            return "Could not create normalized PDF at \(path)."
        }
    }
}

enum PDFDocumentNormalizer {
    private static let mirroredPattern = try! NSRegularExpression(
        pattern: #"(\d+)\s+0\s+0\s+(-\d+)\s+[\d.]+\s+[\d.]+\s*Tm"#,
        options: []
    )

    static func normalizedURLIfNeeded(for sourceURL: URL) throws -> URL {
        // The stored QB-export PDFs are now pre-corrected on disk (the 19 that were
        // vertically flipped were un-flipped by scripts/pdf_unmirror.swift; all are
        // OCR-verified legible). The old on-open flip is therefore disabled: its
        // `isMirrored` heuristic matched the standard top-down text matrix
        // (`N 0 0 -N x y Tm`) in essentially EVERY PDF, so it flipped clean documents
        // into garbage on open. Opening the source file as-is is now always correct.
        return sourceURL
    }

    /// Legacy on-the-fly flip (no longer used in the open path). Kept for reference.
    @available(*, deprecated, message: "Documents are pre-corrected on disk; do not flip on open.")
    static func legacyNormalizedURLIfNeeded(for sourceURL: URL) throws -> URL {
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            return sourceURL
        }

        let outputURL = try cacheURL(for: sourceURL)
        if isFreshCache(sourceURL: sourceURL, cacheURL: outputURL) {
            return outputURL
        }

        guard let document = CGPDFDocument(sourceURL as CFURL), let firstPage = document.page(at: 1) else {
            throw PDFDocumentNormalizerError.unreadableDocument(sourceURL.path)
        }
        guard isMirrored(firstPage) else {
            return sourceURL
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeNormalizedCopy(document: document, to: outputURL)
        return outputURL
    }

    private static func cacheURL(for sourceURL: URL) throws -> URL {
        let values = try sourceURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedStamp = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let sizeStamp = values.fileSize ?? 0
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let root = support
            .appendingPathComponent("RenaissanceLedger", isDirectory: true)
            .appendingPathComponent("normalized_documents", isDirectory: true)
        let safeStem = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(safeStem)__\(sizeStamp)__\(modifiedStamp).pdf"
        return root.appendingPathComponent(fileName)
    }

    private static func isFreshCache(sourceURL: URL, cacheURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return false
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard
            let sourceValues = try? sourceURL.resourceValues(forKeys: keys),
            let cacheValues = try? cacheURL.resourceValues(forKeys: keys)
        else {
            return false
        }
        let sourceModified = sourceValues.contentModificationDate ?? .distantPast
        let cacheModified = cacheValues.contentModificationDate ?? .distantPast
        let cacheSize = cacheValues.fileSize ?? 0
        return cacheModified >= sourceModified && cacheSize > 0
    }

    private static func isMirrored(_ page: CGPDFPage) -> Bool {
        guard let data = contentData(for: page) else {
            return false
        }
        guard let text = String(data: data, encoding: .isoLatin1) else {
            return false
        }
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        return mirroredPattern.numberOfMatches(in: text, options: [], range: fullRange) >= 2
    }

    private static func contentData(for page: CGPDFPage) -> Data? {
        guard let pageDictionary = page.dictionary else {
            return nil
        }

        var contentsObject: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(pageDictionary, "Contents", &contentsObject) else {
            return nil
        }
        guard let contentObjectRef = contentsObject else {
            return nil
        }

        switch CGPDFObjectGetType(contentObjectRef) {
        case .stream:
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(contentObjectRef, .stream, &stream) else {
                return nil
            }
            guard let streamRef = stream else {
                return nil
            }
            var format = CGPDFDataFormat.raw
            return CGPDFStreamCopyData(streamRef, &format) as Data?
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(contentObjectRef, .array, &array) else {
                return nil
            }
            guard let arrayRef = array else {
                return nil
            }
            var combined = Data()
            for index in 0 ..< CGPDFArrayGetCount(arrayRef) {
                var stream: CGPDFStreamRef?
                if CGPDFArrayGetStream(arrayRef, index, &stream), let streamRef = stream {
                    var format = CGPDFDataFormat.raw
                    if let streamData = CGPDFStreamCopyData(streamRef, &format) as Data? {
                        combined.append(streamData)
                    }
                }
            }
            return combined.isEmpty ? nil : combined
        default:
            return nil
        }
    }

    private static func writeNormalizedCopy(document: CGPDFDocument, to outputURL: URL) throws {
        guard let firstPage = document.page(at: 1) else {
            throw PDFDocumentNormalizerError.unreadableDocument(outputURL.path)
        }

        var firstBox = firstPage.getBoxRect(.mediaBox)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL) else {
            throw PDFDocumentNormalizerError.failedCreatingOutput(outputURL.path)
        }
        guard let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            throw PDFDocumentNormalizerError.failedCreatingOutput(outputURL.path)
        }

        for pageIndex in 1 ... document.numberOfPages {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            let mediaBox = page.getBoxRect(.mediaBox)
            let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: mediaBox]
            context.beginPDFPage(pageInfo as CFDictionary)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
    }
}
