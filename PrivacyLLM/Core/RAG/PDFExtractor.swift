import Foundation
import PDFKit

nonisolated struct ExtractedPage: Hashable, Sendable {
    var pageNumber: Int
    var text: String
}

/// PDFKit text extraction with the v1 rejection rules (FR-31): not a PDF,
/// password-protected, or image-only/scanned (no OCR in v1).
nonisolated enum PDFExtractor {
    static func extract(from url: URL, maxPages: Int) throws -> [ExtractedPage] {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.notAPDF
        }
        if document.isLocked || document.isEncrypted {
            throw DocumentError.passwordProtected
        }
        guard document.pageCount <= maxPages else {
            throw DocumentError.documentTooLarge(maxPages: maxPages)
        }

        var pages: [ExtractedPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                pages.append(ExtractedPage(pageNumber: index + 1, text: text))
            }
        }
        guard !pages.isEmpty else {
            throw DocumentError.noExtractableText
        }
        return pages
    }
}
