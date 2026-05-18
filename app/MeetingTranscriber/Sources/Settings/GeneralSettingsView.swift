import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    var updateChecker: UpdateChecker?

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

            Section {
                ForEach($settings.websiteWatchEntries) { $entry in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $entry.enabled).labelsHidden()
                            .accessibilityLabel("Enable \(entry.name)")
                            .disabled(entry.titleContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $entry.name)
                            TextField("Window title contains", text: $entry.titleContains)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Button(role: .destructive) {
                            settings.websiteWatchEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    settings.websiteWatchEntries.append(
                        WebsiteWatchEntry(name: "", titleContains: "", enabled: true)
                    )
                } label: {
                    Label("Add Website", systemImage: "plus.circle")
                }
            } header: {
                Text("Websites to Watch")
            } footer: {
                Text("Detects browser tabs whose window title contains the specified text.")
                    .foregroundStyle(.secondary)
            }

            Section("Detection") {
                HStack {
                    Text("Poll Interval")
                    Spacer()
                    TextField("", value: $settings.pollInterval, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: settings.pollInterval) { _, newValue in
                            settings.pollInterval = min(max(newValue, 1), 30)
                        }
                    Stepper("Poll interval in seconds", value: $settings.pollInterval, in: 1 ... 30, step: 0.5)
                        .labelsHidden()
                    Text("seconds").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Grace Period")
                    Spacer()
                    TextField("", value: $settings.endGrace, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: settings.endGrace) { _, newValue in
                            settings.endGrace = min(max(newValue, 1), 120)
                        }
                    Stepper("Grace period in seconds", value: $settings.endGrace, in: 1 ... 120, step: 1)
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

    private var recordOnlyBanner: some View {
        let display = OutputSettingsLogic.displayPath(
            for: settings.effectiveOutputDir.appendingPathComponent("recordings"),
            home: FileManager.default.homeDirectoryForCurrentUser,
        )
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Record-only mode is active.")
                    .font(.callout.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("Files land in ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(display)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 2) {
                        Text("Each recording gets a ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("<timestamp>_meta.json")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(" sidecar next to its WAVs. No transcription, diarization, or protocol generation runs on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

            if settings.checkForUpdates {
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
}
