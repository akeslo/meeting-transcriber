import SwiftUI

struct NamedPromptEditSheet: View {
    let prompt: NamedPrompt?
    let onSave: (NamedPrompt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var content: String

    init(prompt: NamedPrompt?, onSave: @escaping (NamedPrompt) -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        _name = State(initialValue: prompt?.name ?? "")
        _content = State(initialValue: prompt?.content ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(prompt == nil ? "New Prompt" : "Edit Prompt")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Weekly Standup", text: $name)
                    .textFieldStyle(.roundedBorder)

                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1),
                    )
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let saved = NamedPrompt(
                        id: prompt?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        content: content.trimmingCharacters(in: .whitespaces),
                    )
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}
