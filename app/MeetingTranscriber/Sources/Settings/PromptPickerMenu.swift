import SwiftUI

/// Compact menu button for picking a named prompt.
/// Shows the selected prompt name (or "Default") and a chevron.
struct PromptPickerMenu: View {
    @Binding var promptID: UUID?
    let prompts: [NamedPrompt]

    private var label: String {
        guard let id = promptID,
              let match = prompts.first(where: { $0.id == id })
        else { return "Default" }
        return match.name
    }

    var body: some View {
        Menu {
            Button("Default") { promptID = nil }
            if !prompts.isEmpty {
                Divider()
                ForEach(prompts) { prompt in
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
