import PrivacyUI
import SwiftUI

/// Read-only "what's happening in this chat" sheet (FR-24): context-window
/// usage plus cumulative token and web-search counts. Reached from the chat's
/// ellipsis menu.
struct SessionInfoView: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var stats: SessionStats?

    var body: some View {
        NavigationStack {
            Form {
                if let stats {
                    contextSection(stats)
                    usageSection(stats)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .pvListRow()
                }
            }
            .scrollContentBackground(.hidden)
            .pvScreen()
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { stats = await viewModel.sessionStats() }
    }

    private func contextSection(_ stats: SessionStats) -> some View {
        Section {
            LabeledContent("Model", value: stats.modelName)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Context used")
                    Spacer()
                    Text("\(stats.contextUsed) / \(stats.contextWindow)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                PVProgressBar(value: stats.usageFraction)
            }
            .padding(.vertical, 2)
            if stats.isCompacting {
                Label(
                    "Context is full — older messages are automatically left out so replies stay accurate.",
                    systemImage: "arrow.down.right.and.arrow.up.left"
                )
                .font(.footnote)
                .foregroundStyle(Color.pvWarning)
            }
        } header: {
            Text("Context window")
        } footer: {
            Text("Auto-sized to the model and your device's memory. When the chat outgrows it, the oldest turns roll out of context.")
        }
        .pvListRow()
    }

    private func usageSection(_ stats: SessionStats) -> some View {
        Section("This conversation") {
            LabeledContent("Tokens used (input)", value: stats.promptTokensTotal.formatted())
            LabeledContent("Tokens generated", value: stats.completionTokensTotal.formatted())
            LabeledContent("Web searches", value: stats.webSearchCount.formatted())
            if let tps = stats.lastTokensPerSecond {
                LabeledContent("Last speed", value: "\(tps.formatted(.number.precision(.fractionLength(1)))) tok/s")
            }
        }
        .pvListRow()
    }
}

#Preview {
    SessionInfoView(viewModel: ChatViewModel(conversation: .preview, environment: .mock()))
}
