import SwiftUI

/// Compact menu button for picking a named prompt.
/// Shows the selected prompt name (or the default prompt name, or "Default") and a chevron.
struct PromptPickerMenu: View {
    @Binding var promptID: UUID?
    let prompts: [NamedPrompt]
    var defaultPromptID: UUID? = nil

    private var defaultPromptName: String? {
        guard let id = defaultPromptID else { return nil }
        return prompts.first(where: { $0.id == id })?.name
    }

    private var label: String {
        if let id = promptID, let match = prompts.first(where: { $0.id == id }) {
            return match.name
        }
        return defaultPromptName.map { "\($0) (default)" } ?? "Default"
    }

    var body: some View {
        Menu {
            Button(defaultPromptName.map { "\($0) (default)" } ?? "Default") { promptID = nil }
            let nonDefaultPrompts = prompts.filter { $0.id != defaultPromptID }
            if !nonDefaultPrompts.isEmpty {
                Divider()
                ForEach(nonDefaultPrompts) { prompt in
                    Button(prompt.name) { promptID = prompt.id }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(promptID == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
