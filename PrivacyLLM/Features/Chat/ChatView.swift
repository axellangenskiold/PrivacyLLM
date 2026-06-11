import Combine
import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    @FocusState private var inputFocused: Bool

    init(conversation: Conversation, environment: AppEnvironment) {
        _viewModel = State(initialValue: ChatViewModel(conversation: conversation, environment: environment))
    }

    var body: some View {
        VStack(spacing: 0) {
            if thermalState == .serious || thermalState == .critical {
                thermalBanner
            }
            messageList
            inputBar
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: roleBinding) {
                    Text("Fast").tag(ModelRole.fast)
                    Text("Thinking").tag(ModelRole.thinking)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .accessibilityLabel("Model mode")
            }
        }
        .task { await viewModel.loadMessages() }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private var roleBinding: Binding<ModelRole> {
        Binding(
            get: { viewModel.activeRole },
            set: { viewModel.setActiveRole($0) }
        )
    }

    private var thermalBanner: some View {
        Label("Device is warm — Fast mode is recommended", systemImage: "thermometer.high")
            .font(.footnote)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.15))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty, !viewModel.isBusy {
                        emptyHint
                            .padding(.top, 48)
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }
                    streamingRow
                    if let error = viewModel.errorMessage {
                        errorRow(error)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("bottom")
            }
            .onChange(of: viewModel.streamingReasoning) {
                proxy.scrollTo("bottom")
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    @ViewBuilder
    private var streamingRow: some View {
        if !viewModel.streamingText.isEmpty || !viewModel.streamingReasoning.isEmpty {
            StreamingBubble(text: viewModel.streamingText, reasoning: viewModel.streamingReasoning)
        } else if case .loadingModel(let progress) = viewModel.phase {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(maxWidth: 160)
                Text("Loading model…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if viewModel.phase == .generating {
            HStack(spacing: 8) {
                ProgressView()
                Text("Thinking…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Private chat")
                .font(.headline)
            Text("Everything here is generated and stored on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
            Spacer()
            Button("Dismiss") { viewModel.dismissError() }
                .font(.footnote.bold())
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .focused($inputFocused)
                .accessibilityLabel("Message input")
            if viewModel.isBusy {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                }
                .accessibilityLabel("Stop generating")
            } else {
                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: .preview, environment: AppEnvironment.mock())
    }
}
