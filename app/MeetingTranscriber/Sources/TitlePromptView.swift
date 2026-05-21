import SwiftUI

struct TitlePromptView: View {
    let watchLoop: WatchLoop?

    @State private var titleText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name this recording")
                .font(.headline)

            TextField("Meeting title", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirm() }

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
        .frame(width: 380)
        .onAppear {
            titleText = watchLoop?.pendingTitle?.suggestedTitle ?? ""
        }
        .onChange(of: watchLoop?.pendingTitle?.suggestedTitle) { _, newTitle in
            if let newTitle {
                titleText = newTitle
            } else {
                // Entry cleared externally (auto-flushed by second recording) — close
                dismiss()
            }
        }
    }

    private func confirm() {
        watchLoop?.confirmTitle(titleText)
        dismiss()
    }
}
