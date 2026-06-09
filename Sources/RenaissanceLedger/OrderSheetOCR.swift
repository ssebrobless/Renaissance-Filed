import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

enum OrderSheetOCRError: LocalizedError {
    case unreadableDocument

    var errorDescription: String? {
        switch self {
        case .unreadableDocument:
            return "The selected order sheet file could not be read."
        }
    }
}

enum OrderSheetOCR {
    static func prepareStagedDocument(from sourceURL: URL, sha256: String, destinationDirectory: URL) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "pdf" {
            let destinationURL = destinationDirectory.appendingPathComponent("\(sha256).pdf")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
            return destinationURL
        }

        let cgImage = try loadCGImage(from: sourceURL)
        let destinationURL = destinationDirectory.appendingPathComponent("\(sha256).png")
        try writePNG(cgImage: cgImage, to: destinationURL)
        return destinationURL
    }

    static func recognizeLines(in imageURL: URL) throws -> [OrderSheetOCRLine] {
        let cgImage = try loadCGImage(from: resolvedVisualURL(for: imageURL))

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { observation -> OrderSheetOCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return OrderSheetOCRLine(
                    id: UUID().uuidString,
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    minX: Double(box.origin.x),
                    minY: Double(box.origin.y),
                    width: Double(box.size.width),
                    height: Double(box.size.height)
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.minY - rhs.minY) > 0.02 {
                    return lhs.minY > rhs.minY
                }
                return lhs.minX < rhs.minX
            }
    }

    static func previewImage(for fileURL: URL) -> NSImage? {
        let resolvedURL = resolvedVisualURL(for: fileURL)
        if resolvedURL.pathExtension.lowercased() == "pdf" {
            guard let cgImage = try? loadPDFPageImage(from: resolvedURL) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        guard let cgImage = try? loadCGImage(from: resolvedURL) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func loadCGImage(from url: URL) throws -> CGImage {
        if url.pathExtension.lowercased() == "pdf" {
            return try loadPDFPageImage(from: url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OrderSheetOCRError.unreadableDocument
        }

        let maxDimension = max(pixelSize(from: source), 2400)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        if let transformed = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return transformed
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OrderSheetOCRError.unreadableDocument
        }
        return image
    }

    private static func pixelSize(from source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return 2400
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height, 2400)
    }

    private static func loadPDFPageImage(from url: URL) throws -> CGImage {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0)
        else {
            throw OrderSheetOCRError.unreadableDocument
        }

        let bounds = page.bounds(for: .mediaBox)
        let targetSize = NSSize(
            width: max(bounds.width * 2, 1),
            height: max(bounds.height * 2, 1)
        )
        let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
        var proposedRect = NSRect(origin: .zero, size: thumbnail.size)
        guard let image = thumbnail.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw OrderSheetOCRError.unreadableDocument
        }
        return image
    }

    private static func resolvedVisualURL(for fileURL: URL) -> URL {
        guard fileURL.pathExtension.lowercased() == "pdf" else { return fileURL }
        return (try? PDFDocumentNormalizer.normalizedURLIfNeeded(for: fileURL)) ?? fileURL
    }

    private static func writePNG(cgImage: CGImage, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw OrderSheetOCRError.unreadableDocument
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OrderSheetOCRError.unreadableDocument
        }
    }
}
