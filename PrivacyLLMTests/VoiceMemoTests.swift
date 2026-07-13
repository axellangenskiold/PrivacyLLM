import Foundation
import Testing
@testable import PrivacyLLM

struct VoiceMemoStoreTests {
    private func tempStore() -> VoiceMemoStore {
        VoiceMemoStore(directory: FileManager.default.temporaryDirectory.appending(path: "vm-\(UUID().uuidString)"))
    }

    @Test func roundTripUpdatePositionAndDelete() throws {
        let store = tempStore()
        #expect(store.all().isEmpty)

        let (fileName, url) = store.newAudioFile()
        try Data("audio".utf8).write(to: url)
        let memo = VoiceMemo(title: "Hello", audioFileName: fileName, durationSeconds: 3, voiceQuality: .standard)
        store.upsert(memo)
        #expect(store.all().count == 1)

        store.updatePosition(memo.id, seconds: 1.5)
        #expect(store.all().first?.positionSeconds == 1.5)

        store.delete(memo)
        #expect(store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path)) // audio file cleaned up
    }
}

struct VoiceMemoDraftTests {
    /// A forwarded conversation becomes a two-voice script; system/tool/
    /// attachment rows and empty turns are skipped.
    @Test func conversationBecomesTwoVoiceScript() {
        let conversation = Conversation(title: "Weather")
        let id = conversation.id
        let messages = [
            Message(conversationID: id, role: .system, content: "be nice"),
            Message(conversationID: id, role: .user, content: "Hi"),
            Message(conversationID: id, role: .assistant, content: "Hello!"),
            Message(conversationID: id, role: .tool, content: "tool output"),
            Message(conversationID: id, role: .attachment, content: "doc.pdf"),
            Message(conversationID: id, role: .assistant, content: "   "),
        ]

        let draft = VoiceMemoDraft.fromConversation(conversation, messages: messages)
        #expect(draft.title == "Weather")
        #expect(draft.lines == [SpokenLine("Hi", role: .secondary), SpokenLine("Hello!", role: .primary)])
        #expect(!draft.isEmpty)
    }

    @Test func pastedTextIsOnePrimaryLine() {
        let draft = VoiceMemoDraft(text: "read this", title: "Note")
        #expect(draft.lines == [SpokenLine("read this", role: .primary)])
    }
}

struct MockTTSTests {
    @Test func synthesisWritesFileAndReportsDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "tts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "out.m4a")

        let duration = try await MockTTSService().synthesize(lines: [SpokenLine("Hello world")], quality: .standard, to: url)
        #expect(duration > 0)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func emptyTextThrows() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "empty-\(UUID().uuidString).m4a")
        await #expect(throws: TTSError.self) {
            try await MockTTSService().synthesize(lines: [SpokenLine("   ")], quality: .standard, to: url)
        }
    }
}

@MainActor
struct VoiceMemoViewModelTests {
    @Test func loadsNewestFirst() async {
        let environment = AppEnvironment.mock()
        let store = environment.voiceMemoStore
        store.upsert(VoiceMemo(
            title: "old", audioFileName: "o.m4a", durationSeconds: 1,
            createdAt: Date(timeIntervalSince1970: 100), voiceQuality: .standard
        ))
        store.upsert(VoiceMemo(
            title: "new", audioFileName: "n.m4a", durationSeconds: 1,
            createdAt: Date(timeIntervalSince1970: 200), voiceQuality: .standard
        ))

        let viewModel = VoiceMemoViewModel(environment: environment)
        viewModel.load()
        #expect(viewModel.memos.map(\.title) == ["new", "old"])
    }
}
