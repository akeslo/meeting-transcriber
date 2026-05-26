import SwiftUI

struct TitlePromptView: View {
    let watchLoop: WatchLoop?
    let namedPrompts: [NamedPrompt]

    @State private var titleText: String = ""
    @State private var selectedPromptID: UUID? = nil
    @State private var isManualRecording: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var hasPrompts: Bool { !namedPrompts.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name this recording")
                .font(.headline)

            TextField("Meeting title", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirm() }

            if hasPrompts {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Prompt", selection: $selectedPromptID) {
                        Text("Default (built-in)").tag(UUID?.none)
                        ForEach(namedPrompts) { prompt in
                            Text(prompt.name).tag(UUID?.some(prompt.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            HStack {
                Spacer()
                Button("Skip") {
                    watchLoop?.skipTitle()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            titleText = watchLoop?.pendingTitle?.suggestedTitle ?? ""
            selectedPromptID = watchLoop?.pendingTitle?.suggestedPromptID
            isManualRecording = watchLoop?.pendingTitle?.suggestedPromptID == nil
        }
        .onChange(of: watchLoop?.pendingTitle?.suggestedTitle) { _, newTitle in
            if let newTitle {
                titleText = newTitle
            } else {
                dismiss()
            }
        }
    }

    private func confirm() {
        let resolvedPromptText: String?
        if let id = selectedPromptID {
            resolvedPromptText = namedPrompts.first(where: { $0.id == id })?.content
        } else {
            resolvedPromptText = nil
        }
        watchLoop?.confirmTitle(titleText, promptText: resolvedPromptText)
        dismiss()
    }
}
