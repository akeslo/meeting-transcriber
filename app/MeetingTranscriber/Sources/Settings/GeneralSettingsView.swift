import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    var updateChecker: UpdateChecker?

    @State private var showAddWebsite = false
    @State private var editingWebsite: WatchedWebsite?

    var body: some View {
        // swiftlint:disable:next closure_body_length
        Form {
            Section("Mode") {
                Toggle("Record-only mode", isOn: $settings.recordOnly)
                    .accessibilityIdentifier("recordOnlyToggle")
                if settings.recordOnly {
                    recordOnlyBanner
                }
            }

            Section("Apps to Watch") {
                Toggle("Microsoft Teams", isOn: $settings.watchTeams)
                Toggle("Zoom", isOn: $settings.watchZoom)
                Toggle("Webex", isOn: $settings.watchWebex)
            }

            watchedWebsitesSection

            Section("Detection") {
                HStack {
                    Text("Poll Interval")
                    Spacer()
                    TextField("", value: $settings.pollInterval, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.pollInterval, in: 1 ... 30, step: 0.5)
                        .labelsHidden()
                    Text("seconds").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Grace Period")
                    Spacer()
                    TextField("", value: $settings.endGrace, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.endGrace, in: 1 ... 120, step: 1)
                        .labelsHidden()
                    Text("seconds").foregroundStyle(.secondary)
                }
            }

            if let updateChecker {
                updatesSection(updateChecker: updateChecker)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var watchedWebsitesSection: some View {
        Section("Watched Websites") {
            Picker("Browser", selection: $settings.watchedBrowser) {
                Text("All Browsers").tag("")
                ForEach(BrowserTabDetector.knownBrowsers, id: \.processName) { b in
                    Text(b.processName).tag(b.processName)
                }
            }
            ForEach($settings.watchedWebsites) { $site in
                WatchedWebsiteRow(site: $site) {
                    settings.watchedWebsites.removeAll { $0.id == site.id }
                } onEdit: {
                    editingWebsite = site
                }
            }
            Button("Add Website") { showAddWebsite = true }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
        }
        .sheet(isPresented: $showAddWebsite) {
            WebsiteEditSheet(website: nil) { site in
                settings.watchedWebsites.append(site)
            }
        }
        .sheet(item: $editingWebsite) { site in
            WebsiteEditSheet(website: site) { updated in
                if let i = settings.watchedWebsites.firstIndex(where: { $0.id == updated.id }) {
                    settings.watchedWebsites[i] = updated
                }
            }
        }
    }

    private var recordOnlyBanner: some View {
        let display = OutputSettingsLogic.displayPath(
            for: settings.effectiveOutputDir.appendingPathComponent("recordings"),
            home: FileManager.default.homeDirectoryForCurrentUser,
        )
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Record-only mode is active.")
                    .font(.callout.weight(.semibold))
                Text(
                    "Files land in `\(display)`. Each recording gets a `<timestamp>_meta.json` " +
                        "sidecar next to its WAVs. No transcription, diarization, or protocol " +
                        "generation runs on this device.",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("recordOnlyBanner")
    }

    private func updatesSection(updateChecker: UpdateChecker) -> some View {
        // swiftlint:disable:next closure_body_length
        Section("Updates") {
            Toggle("Check for Updates", isOn: $settings.checkForUpdates)

            if settings.checkForUpdates {
                Toggle("Include Pre-Releases", isOn: $settings.includePreReleases)
            }

            HStack {
                Button {
                    updateChecker.checkNow(
                        includePreReleases: settings.includePreReleases,
                    )
                } label: {
                    HStack(spacing: 4) {
                        if updateChecker.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Check Now")
                    }
                }
                .disabled(updateChecker.isChecking)

                if let error = updateChecker.lastError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if let update = updateChecker.availableUpdate {
                    Label(
                        "Update available: \(update.tagName)",
                        systemImage: "arrow.down.circle.fill",
                    )
                    .foregroundStyle(.blue)
                    .font(.caption)
                } else if updateChecker.lastCheckDate != nil {
                    Label("Up to date", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if let update = updateChecker.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.dmgURL ?? update.htmlURL)
                } label: {
                    Label(
                        "Download \(update.tagName)",
                        systemImage: "arrow.down.to.line",
                    )
                }
            }
        }
    }
}

struct WatchedWebsiteRow: View {
    @Binding var site: WatchedWebsite
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: $site.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                    HStack(spacing: 6) {
                        Text(site.urlPattern)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if site.recordMic {
                            Label("Mic", systemImage: "mic.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            Spacer()
            Button { onEdit() } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
        }
    }
}

struct WebsiteEditSheet: View {
    let website: WatchedWebsite?
    let onSave: (WatchedWebsite) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var urlPattern: String
    @State private var recordMic: Bool

    init(website: WatchedWebsite?, onSave: @escaping (WatchedWebsite) -> Void) {
        self.website = website
        self.onSave = onSave
        _name = State(initialValue: website?.name ?? "")
        _urlPattern = State(initialValue: website?.urlPattern ?? "")
        _recordMic = State(initialValue: website?.recordMic ?? false)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !urlPattern.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(website == nil ? "Add Website" : "Edit Website")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("URL or domain (e.g. youtube.com)", text: $urlPattern)
                    .textFieldStyle(.roundedBorder)
                Toggle("Record microphone", isOn: $recordMic)
            }
            .formStyle(.columns)

            Text("Recording starts when any open tab URL contains this text.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let saved = WatchedWebsite(
                        id: website?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        urlPattern: urlPattern.trimmingCharacters(in: .whitespaces),
                        enabled: website?.enabled ?? true,
                        recordMic: recordMic,
                    )
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
