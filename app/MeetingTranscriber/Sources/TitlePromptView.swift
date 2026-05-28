import SwiftUI

struct TitlePromptView: View {
    let watchLoop: WatchLoop?
    let namedPrompts: [NamedPrompt]
    var defaultPromptID: UUID? = nil

    @State private var titleText: String = ""
    @State private var selectedPromptID: UUID? = nil
    @State private var didConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var hasPrompts: Bool { !namedPrompts.isEmpty }

    private func defaultPromptLabel() -> String {
        guard let id = defaultPromptID,
              let name = namedPrompts.first(where: { $0.id == id })?.name
        else { return "Default" }
        return "\(name) (default)"
    }

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
                        Text(defaultPromptLabel()).tag(UUID?.none)
                        let nonDefault = namedPrompts.filter { $0.id != defaultPromptID }
                        if !nonDefault.isEmpty {
                            Divider()
                            ForEach(nonDefault) { prompt in
                                Text(prompt.name).tag(UUID?.some(prompt.id))
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            HStack {
                Spacer()
                Button("Skip") { skip() }
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
            // Per-app prompt → global default → nil
            selectedPromptID = watchLoop?.pendingTitle?.suggestedPromptID ?? defaultPromptID
        }
        .onChange(of: watchLoop?.pendingTitle?.suggestedTitle) { _, newTitle in
            if let newTitle {
                titleText = newTitle
            } else {
                dismiss()
            }
        }
        .onDisappear {
            // X button or other non-Save/Skip dismiss: auto-skip so recording isn't lost.
            if !didConfirm {
                watchLoop?.skipTitle()
            }
        }
    }

    private func confirm() {
        let resolvedPromptText: String?
        if let id = selectedPromptID {
            resolvedPromptText = namedPrompts.first(where: { $0.id == id })?.content
        } else {
            // nil selectedPromptID means "use default" — resolved by the pipeline
            resolvedPromptText = nil
        }
        didConfirm = true
        watchLoop?.confirmTitle(titleText, promptText: resolvedPromptText)
        dismiss()
    }

    private func skip() {
        didConfirm = true
        watchLoop?.skipTitle()
        dismiss()
    }
}
