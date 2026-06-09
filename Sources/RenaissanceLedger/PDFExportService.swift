import AppKit
import SwiftUI

enum PDFExportServiceError: LocalizedError {
    case unableToCreatePDF
    case emailUnavailable

    var errorDescription: String? {
        switch self {
        case .unableToCreatePDF:
            return "Could not create a PDF for this document."
        case .emailUnavailable:
            return "Mail could not be opened for PDF email."
        }
    }
}

@MainActor
enum PDFExportService {
    private static let pageSize = CGSize(width: 612, height: 792)

    static func printView<V: View>(jobTitle: String, view: V) {
        let hostView = hostingView(for: view)
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: pageSize.width, height: pageSize.height)
        printInfo.topMargin = 18
        printInfo.bottomMargin = 18
        printInfo.leftMargin = 18
        printInfo.rightMargin = 18
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = NSPrintOperation(view: hostView, printInfo: printInfo)
        operation.jobTitle = jobTitle
        operation.run()
    }

    static func emailPDF<V: View>(fileName: String, subject: String, view: V) throws {
        let pdfURL = try writePDF(fileName: fileName, view: view)
        guard let service = NSSharingService(named: .composeEmail) else {
            throw PDFExportServiceError.emailUnavailable
        }
        service.subject = subject
        service.perform(withItems: [pdfURL])
    }

    static func writePDF<V: View>(fileName: String, view: V) throws -> URL {
        let hostView = hostingView(for: view)
        let data = hostView.dataWithPDF(inside: hostView.bounds)
        guard !data.isEmpty else {
            throw PDFExportServiceError.unableToCreatePDF
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitizedFileName(fileName))
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func hostingView<V: View>(for view: V) -> NSHostingView<V> {
        let hostView = NSHostingView(rootView: view)
        hostView.frame = CGRect(origin: .zero, size: pageSize)
        hostView.layoutSubtreeIfNeeded()
        return hostView
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.replacingOccurrences(of: "/", with: "-")
        return safe.lowercased().hasSuffix(".pdf") ? safe : "\(safe).pdf"
    }
}
