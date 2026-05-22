import SwiftData
import SwiftUI

struct LibraryView: View {
    var pipelineQueue: PipelineQueue
    @Binding var selectedSessionID: UUID?
    var onDeleteSession: (RecordingSession) -> Void

    @Query(sort: \RecordingSession.createdAt, order: .reverse)
    private var sessions: [RecordingSession]

    @State private var searchText: String = ""
    @State private var isGridLayout: Bool = false

    // MARK: - Static helpers (testable)

    static func filterSessions(_ sessions: [RecordingSession], searchText: String) -> [RecordingSession] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter { s in
            s.title.localizedCaseInsensitiveContains(searchText)
                || s.appName.localizedCaseInsensitiveContains(searchText)
                || s.participantNames.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
    }

    static func filterInFlightJobs(_ jobs: [PipelineJob]) -> [PipelineJob] {
        let activeStates: Set<JobState> = [.waiting, .transcribing, .diarizing, .generatingProtocol]
        return jobs.filter { activeStates.contains($0.state) }
    }

    // MARK: - Computed

    private var filteredSessions: [RecordingSession] {
        Self.filterSessions(sessions, searchText: searchText)
    }

    private var inFlightJobs: [PipelineJob] {
        Self.filterInFlightJobs(pipelineQueue.jobs)
    }

    private var totalCount: Int {
        sessions.count + inFlightJobs.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recordings · \(totalCount) total item\(totalCount == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isGridLayout.toggle()
                    }
                } label: {
                    Image(systemName: isGridLayout ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help(isGridLayout ? "Switch to list view" : "Switch to grid view")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search…", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if isGridLayout {
                gridContent
            } else {
                listContent
            }
        }
    }

    // MARK: - List layout

    private var listContent: some View {
        List {
            inFlightJobsSection
            sessionListSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if filteredSessions.isEmpty && inFlightJobs.isEmpty {
                emptySearchState
            }
        }
    }

    @ViewBuilder
    private var inFlightJobsSection: some View {
        ForEach(inFlightJobs, id: \.id) { job in
            InFlightRowView(
                job: job,
                isSelected: selectedSessionID == job.id,
                onCancel: { pipelineQueue.cancelJob(id: job.id) }
            )
            .onTapGesture { selectedSessionID = job.id }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var sessionListSection: some View {
        ForEach(filteredSessions, id: \.id) { session in
            sessionListRow(session)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .onDelete { indexSet in
            for index in indexSet {
                onDeleteSession(filteredSessions[index])
            }
        }
    }

    @ViewBuilder
    private func sessionListRow(_ session: RecordingSession) -> some View {
        SessionRowView(
            session: session,
            isSelected: selectedSessionID == session.id,
            onDelete: { onDeleteSession(session) }
        )
        .onTapGesture { selectedSessionID = session.id }
        Divider().padding(.leading, 60)
    }

    // MARK: - Grid layout

    private var gridContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !inFlightJobs.isEmpty {
                    inFlightGridSection
                    Divider().padding(.horizontal, 20).padding(.vertical, 4)
                }
                sessionGrid
                if filteredSessions.isEmpty && inFlightJobs.isEmpty {
                    emptySearchState
                }
            }
        }
    }

    @ViewBuilder
    private var sessionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 12)],
            spacing: 12
        ) {
            ForEach(filteredSessions, id: \.id) { session in
                SessionGridCardView(
                    session: session,
                    isSelected: selectedSessionID == session.id,
                    onDelete: { onDeleteSession(session) }
                )
                .onTapGesture { selectedSessionID = session.id }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var inFlightGridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In Progress")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(inFlightJobs, id: \.id) { job in
                        inFlightGridCard(job)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func inFlightGridCard(_ job: PipelineJob) -> some View {
        let peach = Color(red: 0.969, green: 0.773, blue: 0.624)
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(peach.opacity(0.1))
                Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(peach.opacity(0.6))
            }
            .frame(height: 80)
            Text(job.meetingTitle.isEmpty ? "Recording…" : job.meetingTitle)
                .font(.system(size: 12, weight: .medium)).lineLimit(2)
            if job.progress > 0 {
                ProgressView(value: job.progress).tint(peach)
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .onTapGesture { selectedSessionID = job.id }
    }

    // MARK: - Empty state

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("No recordings yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Recorded meetings will appear here after transcription.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}
