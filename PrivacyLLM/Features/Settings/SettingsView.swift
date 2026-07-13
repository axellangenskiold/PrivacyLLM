import PrivacyUI
import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var confirmClearChats = false
    @State private var confirmClearDocuments = false
    @State private var confirmReset = false

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: SettingsViewModel(environment: environment))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section {
                Toggle("Web Search", isOn: $viewModel.searchEnabled)
                if viewModel.searchEnabled {
                    Picker("Provider", selection: $viewModel.searchProviderID) {
                        ForEach(viewModel.providers) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                }
                NavigationLink {
                    PrivacyExplainerView()
                } label: {
                    Label("What leaves this device", systemImage: "arrow.up.forward.app")
                }
                NavigationLink {
                    PrivacyActivityView(viewModel: viewModel)
                } label: {
                    Label("Privacy Activity", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Search is off by default. When on, only short keyword queries are sent to the provider you choose — never your conversations.")
            }
            .pvListRow()

            Section("Persona") {
                TextField("Global system prompt", text: $viewModel.globalSystemPrompt, axis: .vertical)
                    .lineLimit(2...6)
            }
            .pvListRow()

            Section {
                if !viewModel.downloadedModels.isEmpty {
                    Picker("Fast model", selection: fastBinding) {
                        ForEach(viewModel.downloadedModels) { spec in
                            Text(spec.displayName).tag(spec.id as String?)
                        }
                    }
                    Picker("Thinking model", selection: thinkingBinding) {
                        ForEach(viewModel.downloadedModels) { spec in
                            Text(spec.displayName).tag(spec.id as String?)
                        }
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", viewModel.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.temperature, in: 0...1.5, step: 0.05)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Top-p")
                        Spacer()
                        Text(String(format: "%.2f", viewModel.topP))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.topP, in: 0.1...1, step: 0.05)
                }
                Picker("Max response tokens", selection: $viewModel.maxTokens) {
                    ForEach([256, 512, 1024, 2048], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                Picker("Context length", selection: $viewModel.contextLength) {
                    Text("Auto (match model)").tag(0)
                    ForEach([2048, 4096, 8192], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Higher temperature means more varied replies. Auto sizes context to the model and your device's memory; a fixed value caps it lower to save memory.")
            }
            .pvListRow()

            Section("Appearance") {
                Picker("Theme", selection: $viewModel.appearance) {
                    ForEach(AppearanceSetting.allCases) { setting in
                        Text(setting.label).tag(setting)
                    }
                }
            }
            .pvListRow()

            Section {
                Button("Clear All Conversations", role: .destructive) { confirmClearChats = true }
                Button("Clear Document Library", role: .destructive) { confirmClearDocuments = true }
                Button("Reset App Data", role: .destructive) { confirmReset = true }
            } header: {
                Text("Data")
            } footer: {
                Text("Downloaded models are managed in the Models screen.")
            }
            .pvListRow()

            AboutSection(llamaLicenseURL: viewModel.llamaLicenseURL)
                .pvListRow()
        }
        .scrollContentBackground(.hidden)
        .pvScreen()
        .navigationTitle("Settings")
        .task {
            if !viewModel.loaded { await viewModel.load() }
            await viewModel.refreshModels()
        }
        .confirmationDialog("Delete every conversation?", isPresented: $confirmClearChats, titleVisibility: .visible) {
            Button("Delete All Conversations", role: .destructive) {
                Task { await viewModel.clearAllConversations() }
            }
        }
        .confirmationDialog("Delete all documents and their index?", isPresented: $confirmClearDocuments, titleVisibility: .visible) {
            Button("Delete Documents", role: .destructive) {
                Task { await viewModel.clearDocumentIndex() }
            }
        }
        .confirmationDialog("Erase all chats, documents, and settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset App Data", role: .destructive) {
                Task { await viewModel.resetApp() }
            }
        }
    }

    private var fastBinding: Binding<String?> {
        Binding(
            get: { viewModel.activeFastID },
            set: { if let id = $0 { viewModel.setActiveModel(id, role: .fast) } }
        )
    }

    private var thinkingBinding: Binding<String?> {
        Binding(
            get: { viewModel.activeThinkingID },
            set: { if let id = $0 { viewModel.setActiveModel(id, role: .thinking) } }
        )
    }
}

/// PR-12: the always-available, plain-language egress explainer.
struct PrivacyExplainerView: View {
    var body: some View {
        List {
            Section {
                explainerRow(
                    icon: "iphone",
                    tint: .pvAccent,
                    title: "Stays on this iPhone",
                    detail: "Your messages, the model's replies and reasoning, your documents and their search index, settings, and the privacy activity log. All of it is stored encrypted and never transmitted."
                )
            }
            .pvListRow()
            Section {
                explainerRow(
                    icon: "square.and.arrow.down",
                    tint: .blue,
                    title: "Model downloads",
                    detail: "When you download a model, the app fetches weights from huggingface.co. Nothing about you or your chats is sent — it's a plain file download."
                )
                explainerRow(
                    icon: "magnifyingglass",
                    tint: .pvWarning,
                    title: "Web search (only when you turn it on)",
                    detail: "With search on, the assistant can send short keyword queries to your chosen search provider. The orange banner appears every time this happens, and each query is listed in Privacy Activity. Your conversation text is never sent."
                )
                explainerRow(
                    icon: "apple.logo",
                    tint: .gray,
                    title: "Apple system assets",
                    detail: "iOS may download Apple's language assets for on-device dictation and document indexing the first time you use them. That's an operating-system download from Apple — your content is not involved."
                )
            } header: {
                Text("The only network activity")
            }
            .pvListRow()
            Section {
                Text("There are no analytics, no tracking, no accounts, and no servers of ours. In airplane mode, everything except web search keeps working.")
                    .font(.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
            }
            .pvListRow()
        }
        .scrollContentBackground(.hidden)
        .pvScreen()
        .navigationTitle("What leaves this device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func explainerRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PVFont.headline)
                    .foregroundStyle(Color.pvTextPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.pvTextSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// PR-14: local-only log of every outbound event.
struct PrivacyActivityView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.recentEgressEvents.isEmpty {
                PVEmptyState(
                    icon: "checkmark.shield",
                    title: "Nothing has left this device",
                    message: "Search queries and model downloads will be listed here when they happen."
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.recentEgressEvents) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.kind == .webSearch ? "magnifyingglass" : "square.and.arrow.down")
                            .foregroundStyle(event.kind == .webSearch ? Color.pvWarning : Color.pvAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.detail)
                                .font(.subheadline)
                                .foregroundStyle(Color.pvTextPrimary)
                            Text("\(event.destinationHost) · \(event.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(PVFont.metaSmall)
                                .foregroundStyle(Color.pvTextSecondary)
                        }
                    }
                    .pvListRow()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pvScreen()
        .navigationTitle("Privacy Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.recentEgressEvents.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { viewModel.clearEgressLog() }
                }
            }
        }
        .task { await viewModel.refreshEgressEvents() }
    }
}

private struct AboutSection: View {
    /// Non-nil when a Llama-family model ships in the catalog; carries the URL of
    /// the Llama 3.2 Community License so it can be linked (license §1.b.i).
    let llamaLicenseURL: URL?

    private static let dependencies: [(name: String, license: String, url: String)] = [
        ("GRDB.swift", "MIT", "https://github.com/groue/GRDB.swift"),
        ("MLX Swift / mlx-swift-lm", "MIT", "https://github.com/ml-explore/mlx-swift-lm"),
        ("swift-transformers", "Apache-2.0", "https://github.com/huggingface/swift-transformers"),
        ("swift-huggingface", "Apache-2.0", "https://github.com/huggingface/swift-huggingface"),
        ("SwiftSoup", "MIT", "https://github.com/scinfu/SwiftSoup"),
        ("MarkdownUI", "MIT", "https://github.com/gonzalezreal/swift-markdown-ui"),
        ("Highlightr", "MIT", "https://github.com/raspu/Highlightr"),
    ]

    var body: some View {
        Section {
            LabeledContent("Version") {
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
            }
            NavigationLink("Open Source Licenses") {
                List {
                    Section {
                        ForEach(Self.dependencies, id: \.name) { dependency in
                            if let url = URL(string: dependency.url) {
                                Link(destination: url) {
                                    LabeledContent(dependency.name, value: dependency.license)
                                }
                            }
                        }
                    } footer: {
                        Text("Model licenses are shown per model in the Models screen.")
                    }
                    .pvListRow()
                }
                .scrollContentBackground(.hidden)
                .pvScreen()
                .navigationTitle("Licenses")
                .navigationBarTitleDisplayMode(.inline)
            }
            if let url = URL(string: "https://github.com/axellangenskiold/PrivacyLLM") {
                Link(destination: url) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            if let llamaLicenseURL {
                Link(destination: llamaLicenseURL) {
                    Label("Built with Llama", systemImage: "checkmark.seal")
                }
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("PrivacyLLM runs entirely on your device. We collect nothing — there is nothing to collect it with.")
                if llamaLicenseURL != nil {
                    // Required attribution notice — Llama 3.2 Community License §1.b.i.
                    Text("Llama 3.2 is licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved.")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(environment: AppEnvironment.mock())
    }
}
