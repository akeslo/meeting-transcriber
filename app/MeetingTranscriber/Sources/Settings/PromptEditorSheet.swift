import SwiftUI

struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Protocol Prompt")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { save(); dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .padding(12)

            Divider()

            HStack {
                Button("Reset to Default") {
                    content = ProtocolGenerator.protocolPrompt
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 620, minHeight: 460)
        .onAppear {
            content = (try? String(contentsOf: AppPaths.customPromptFile, encoding: .utf8)) ?? ProtocolGenerator.protocolPrompt
        }
    }

    private func save() {
        let dir = AppPaths.customPromptFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: AppPaths.customPromptFile, atomically: true, encoding: .utf8)
    }
}
