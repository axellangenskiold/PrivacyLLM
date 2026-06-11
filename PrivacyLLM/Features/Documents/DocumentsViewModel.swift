import Foundation
import Observation

@Observable
final class DocumentsViewModel {
    private(set) var documents: [DocumentMeta] = []
    private(set) var isImporting = false
    private(set) var errorMessage: String?

    private let service: any DocumentServicing

    init(environment: AppEnvironment) {
        service = environment.documents
    }

    func refresh() async {
        documents = (try? await service.documents()) ?? []
    }

    func importPDF(at url: URL, scope: DocumentScope) async {
        errorMessage = nil
        isImporting = true
        defer { isImporting = false }
        do {
            _ = try await service.importPDF(at: url, scope: scope)
        } catch {
            errorMessage = Self.message(for: error)
        }
        await refresh()
    }

    func delete(_ document: DocumentMeta) async {
        try? await service.deleteDocument(document.id)
        await refresh()
    }

    static func message(for error: any Error) -> String {
        switch error as? DocumentError {
        case .notAPDF:
            String(localized: "That file isn't a PDF. Only PDF documents are supported.")
        case .passwordProtected:
            String(localized: "This PDF is password-protected and can't be read.")
        case .noExtractableText:
            String(localized: "No text could be extracted — scanned or image-only PDFs aren't supported yet.")
        case .documentTooLarge:
            String(localized: "This document is too large to index.")
        case .corpusFull:
            String(localized: "Your document library is full. Delete a document to make room.")
        case .notFound:
            String(localized: "That document no longer exists.")
        case nil:
            String(localized: "The document couldn't be imported. (\(error.localizedDescription))")
        }
    }
}
