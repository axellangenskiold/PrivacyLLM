import Foundation
import Observation

@Observable
final class ConversationListViewModel {
    private(set) var conversations: [Conversation] = []
    private let store: ConversationStore

    init(environment: AppEnvironment) {
        store = environment.conversationStore
    }

    func refresh() async {
        conversations = (try? await store.fetchAll()) ?? []
    }

    func create() async -> Conversation? {
        let conversation = Conversation()
        do {
            try await store.insert(conversation)
        } catch {
            return nil
        }
        await refresh()
        return conversation
    }

    func rename(_ conversation: Conversation, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = conversation
        updated.title = trimmed
        updated.updatedAt = .now
        try? await store.update(updated)
        await refresh()
    }

    func delete(_ conversation: Conversation) async {
        try? await store.delete(conversation.id)
        await refresh()
    }
}
