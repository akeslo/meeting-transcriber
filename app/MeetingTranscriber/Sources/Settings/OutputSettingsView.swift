import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pure derivations used by `OutputSettingsView`. Extracted so the wrapping
/// logic can be unit-tested without instantiating a SwiftUI host.
enum OutputSettingsLogic {
    /// Abbreviate `url` for display by replacing the home-directory prefix
    /// with `~` so paths inside the user's home stay compact. Falls back to
    /// the full path when `url` is outside `home`. Matches at the path-
    /// component boundary so `home="/Users/alice"` doesn't abbreviate
    /// `/Users/alicebob/...` to `~bob/...`.
    static func displayPath(for url: URL, home: URL) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        let prefixed = homePath.hasSuffix("/") ? homePath : homePath + "/"
        guard path.hasPrefix(prefixed) else { return path }
        return "~/" + path.dropFirst(prefixed.count)
    }

    /// Merge the currently-selected model into a fetched picker list so the
    /// user's choice survives even when `/models` doesn't echo it back
    /// (custom Ollama tags, in-flight rename, offline cache). Returns
    /// `available` unchanged when `selected` is empty or already present.
    static func mergePickerOptions(available: [String], selected: String) -> [String] {
        guard !selected.isEmpty, !available.contains(selected) else { return available }
        return [selected] + available
    }
}

struct OutputSettingsView: View {
    @Bindable var settings: AppSettings

    #if !APPSTORE
        @State private var claudeBinaries: [String] = ["claude"]
    #endif
    @State private var testingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var availableModels: [String] = []
    @State private var didAttemptConnectionTest = false
    @State private var showAddPrompt = false
    @State private var editingPrompt: NamedPrompt?
    @State private var templateToApply: (PromptTemplate, NamedPrompt.ID?)?

    enum PromptTemplate: String, CaseIterable {
        case meeting     = "Meeting Notes"
        case interview   = "Interview Summary"
        case brainstorm  = "Brainstorming Session"
        case statusCall  = "Status / Standup"
        case youTube     = "YouTube Video Summary"

        var prompt: String {
            switch self {
            case .meeting:
                return ProtocolGenerator.protocolPrompt
            case .interview:
                return """
                You are an expert interview analyst.
                Summarize the following interview in {LANGUAGE}.

                Return ONLY the finished Markdown document.

                # Interview Summary - [Title]
                **Date:** [Date]
                **Interviewer:** [Name]
                **Interviewee:** [Name]

                ---

                ## Key Themes
                - [Theme 1]

                ## Notable Quotes
                > "[Quote]" — [Speaker]

                ## Insights & Highlights
                [3-5 paragraphs]

                ## Follow-up Questions
                - [Question]

                ---
                Transcript:
                """
            case .brainstorm:
                return """
                You are a creative facilitator and note-taker.
                Summarize this brainstorming session in {LANGUAGE}.

                Return ONLY the finished Markdown document.

                # Brainstorming Session - [Title]
                **Date:** [Date]

                ---

                ## Goal
                [What the session aimed to solve]

                ## Ideas Generated
                - [Idea 1]
                - [Idea 2]

                ## Top Ideas (shortlisted)
                ### [Idea]
                [Why it stood out]

                ## Next Steps
                - [ ] [Action]

                ---
                Transcript:
                """
            case .statusCall:
                return """
                You are a concise meeting note-taker.
                Summarize this status or standup call in {LANGUAGE}.

                Return ONLY the finished Markdown document.

                # Status Update - [Date]
                **Team / Project:** [Name]

                ---

                ## What was completed
                - [Item]

                ## What's in progress
                - [Item]

                ## Blockers
                - [Blocker or "None"]

                ## Decisions & Actions
                | Action | Owner | Due |
                |--------|-------|-----|
                | [Task] | [Name] | [Date] |

                ---
                Transcript:
                """
            case .youTube:
                return """
                You are an expert content summarizer.
                Summarize the following YouTube video transcript in {LANGUAGE}.

                Return ONLY the finished Markdown document.

                # Video Summary - [Video Title]
                **Channel:** [Channel Name if mentioned]
                **Date:** [Date if mentioned]

                ---

                ## TL;DR
                [2-3 sentence overview of the video]

                ## Key Points
                - [Key point 1]
                - [Key point 2]
                - [Key point 3]

                ## Main Sections
                ### [Section / Topic 1]
                [What was covered, key insights]

                ### [Section / Topic 2]
                [What was covered, key insights]

                ## Notable Quotes
                > "[Quote]"

                ## Takeaways & Action Items
                - [Practical takeaway or action]

                ---
                Transcript:
                """
            }
        }
    }

    enum ConnectionTestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        // swiftlint:disable:next closure_body_length
        Form {
            // Output folder applies to record-only AND protocol mode, so this
            // section deliberately sits outside the .recordOnlyDisabled block.
            Section("Output Folder") {
                HStack {
                    Text("Output Folder")
                    Spacer()
                    Text(outputDirDisplay)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Choose\u{2026}") {
                        chooseOutputFolder()
                    }

                    Button("Reset") {
                        settings.clearCustomOutputDir()
                    }
                    .disabled(settings.customOutputDirBookmark == nil)

                    Spacer()
                }
            }
            .accessibilityIdentifier("outputFolderSection")

            Section("Protocol Generation") {
                Picker("LLM Provider", selection: $settings.protocolProvider) {
                    ForEach(ProtocolProvider.allCases, id: \.self) { provider in
                        Text(provider.label).tag(provider)
                    }
                }

                providerConfigView

                Picker("Protocol Language", selection: $settings.protocolLanguage) {
                    ForEach(AppSettings.protocolLanguages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }

                Toggle("Anonymize transcript before sending to LLM", isOn: $settings.anonymizeTranscript)
                    .help("Replace speaker names with [Speaker A], [Speaker B] in the transcript before protocol generation")
            }
            .accessibilityIdentifier("protocolSection")
            .recordOnlyDisabled(settings.recordOnly)

            namedPromptsSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddPrompt) {
            NamedPromptEditSheet(prompt: nil) { newPrompt in
                settings.namedPrompts.append(newPrompt)
            }
        }
        .sheet(item: $editingPrompt) { prompt in
            NamedPromptEditSheet(prompt: prompt) { updated in
                if let i = settings.namedPrompts.firstIndex(where: { $0.id == updated.id }) {
                    settings.namedPrompts[i] = updated
                }
            }
        }
        .onAppear {
            #if !APPSTORE
                claudeBinaries = ClaudeCLIProtocolGenerator.availableClaudeBinaries()
            #endif
        }
    }

    @ViewBuilder
    private var providerConfigView: some View { // swiftlint:disable:this attributes
        switch settings.protocolProvider {
        #if !APPSTORE
            case .claudeCLI:
                Picker("Claude CLI", selection: $settings.claudeBin) {
                    ForEach(claudeBinaries, id: \.self) { bin in
                        Text(bin).tag(bin)
                    }
                }
                Picker("Model", selection: $settings.claudeModel) {
                    Text("Haiku (fastest)").tag("haiku")
                    Text("Sonnet (balanced)").tag("sonnet")
                    Text("Opus (most capable)").tag("opus")
                }
                Text("Binary used for protocol generation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
        #endif

        case .openAICompatible:
            openAIConfigView

        case .none:
            Text("Only the raw transcript will be saved — no LLM summarization.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var openAIConfigView: some View { // swiftlint:disable:this attributes
        VStack(alignment: .leading, spacing: 4) {
            Text("Endpoint")
            TextField("", text: $settings.openAIEndpoint)
                .textFieldStyle(.roundedBorder)
        }

        if !availableModels.isEmpty {
            Picker("Model", selection: $settings.openAIModel) {
                ForEach(modelPickerOptions, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        } else {
            HStack {
                Text("Model")
                Spacer()
                TextField("", text: $settings.openAIModel)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
            }
        }

        HStack {
            Text("API Key")
            Spacer()
            SecureField("", text: $settings.openAIAPIKey)
                .frame(width: 200)
        }
        Text("Leave empty if your local server doesn't require authentication")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack {
            Button {
                testConnection()
            } label: {
                HStack(spacing: 4) {
                    if testingConnection {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(availableModels.isEmpty ? "Fetch Models" : "Refresh Models")
                }
            }
            .disabled(testingConnection)

            if let result = connectionTestResult {
                switch result {
                case let .success(msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)

                case let .failure(msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .onAppear {
            if availableModels.isEmpty && !didAttemptConnectionTest {
                testConnection()
            }
        }
    }

    // MARK: - Named Prompts Section

    @ViewBuilder
    private var namedPromptsSection: some View {
        Section("Prompts") {
            if settings.namedPrompts.isEmpty {
                Text("No prompts yet. Add one to assign it to apps or websites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($settings.namedPrompts) { $prompt in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.name)
                            Text(prompt.content.prefix(60) + (prompt.content.count > 60 ? "…" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            Button("Edit") { editingPrompt = prompt }
                            Menu("Load Template") {
                                ForEach(PromptTemplate.allCases, id: \.self) { template in
                                    Button(template.rawValue) {
                                        templateToApply = (template, prompt.id)
                                    }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                settings.namedPrompts.removeAll { $0.id == prompt.id }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }

            Button("Add Prompt") { showAddPrompt = true }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
        }
        .confirmationDialog(
            "Replace prompt content with \"\(templateToApply?.0.rawValue ?? "")\" template?",
            isPresented: Binding(
                get: { templateToApply != nil },
                set: { if !$0 { templateToApply = nil } }
            ),
            titleVisibility: .visible,
        ) {
            Button("Load Template", role: .destructive) {
                if let (template, promptID) = templateToApply,
                   let i = settings.namedPrompts.firstIndex(where: { $0.id == promptID }) {
                    settings.namedPrompts[i].content = template.prompt
                }
                templateToApply = nil
            }
            Button("Cancel", role: .cancel) { templateToApply = nil }
        }
    }

    // MARK: - Helpers

    func testConnection() {
        testingConnection = true
        didAttemptConnectionTest = true
        connectionTestResult = nil
        Task {
            let apiKey = settings.openAIAPIKey.isEmpty ? nil : settings.openAIAPIKey
            let result = await OpenAIProtocolGenerator.testConnection(
                endpoint: settings.openAIEndpoint,
                model: settings.openAIModel,
                apiKey: apiKey,
            )
            testingConnection = false
            switch result {
            case let .success(models):
                availableModels = models
                if !models.isEmpty {
                    if !models.contains(settings.openAIModel) {
                        settings.openAIModel = models[0]
                    }
                    connectionTestResult = .success("Connected (\(models.count) models)")
                } else {
                    connectionTestResult = .success("Connected")
                }

            case let .failure(error):
                availableModels = []
                connectionTestResult = .failure(error.localizedDescription)
            }
        }
    }

    private var modelPickerOptions: [String] {
        OutputSettingsLogic.mergePickerOptions(available: availableModels, selected: settings.openAIModel)
    }

    private var outputDirDisplay: String {
        OutputSettingsLogic.displayPath(
            for: settings.effectiveOutputDir,
            home: FileManager.default.homeDirectoryForCurrentUser,
        )
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for protocol output"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setCustomOutputDir(url)
    }
}
