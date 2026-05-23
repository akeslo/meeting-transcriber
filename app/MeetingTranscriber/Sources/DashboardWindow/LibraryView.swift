import SwiftData
import SwiftUI

struct LibraryView: View {
    var pipelineQueue: PipelineQueue
    @Binding var selectedSessionID: UUID?
    var onDeleteSession: (RecordingSession) -> Void

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \RecordingSession.createdAt, order: .reverse)
    private var sessions: [RecordingSession]

    @State private var searchText: String = ""
    @State private var isGridLayout: Bool = false
    @State private var selectedTag: String? = nil
    @State private var selectedFolder: String? = nil
    @State private var sortOrder: SessionSort = .newestFirst
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var showDateFilter: Bool = false
    @State private var fullTextSearchEnabled: Bool = false
    @State private var fullTextMatches: Set<UUID> = []
    @State private var isSearchingFullText: Bool = false
    @State private var isMultiSelectMode: Bool = false
    @State private var multiSelection: Set<UUID> = []

    // MARK: - Sort

    enum SessionSort: String, CaseIterable {
        case newestFirst = "Newest"
        case oldestFirst = "Oldest"
        case longestFirst = "Longest"
        case shortestFirst = "Shortest"
        case titleAZ = "Title A–Z"
    }

    // MARK: - Static helpers (testable)

    static func filterSessions(
        _ sessions: [RecordingSession],
        searchText: String,
        tag: String? = nil,
        folder: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        fullTextIDs: Set<UUID>? = nil
    ) -> [RecordingSession] {
        sessions.filter { s in
            let matchesSearch = searchText.isEmpty
                || s.title.localizedCaseInsensitiveContains(searchText)
                || s.appName.localizedCaseInsensitiveContains(searchText)
                || s.participantNames.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
                || (fullTextIDs?.contains(s.id) ?? false)
            let matchesTag = tag == nil || s.tags.contains(tag!)
            let matchesFolder = folder == nil || s.folderGroup == folder!
            let matchesStart = startDate == nil || s.createdAt >= startDate!
            let matchesEnd = endDate == nil || s.createdAt <= (endDate.map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 } ?? Date.distantFuture)
            return matchesSearch && matchesTag && matchesFolder && matchesStart && matchesEnd
        }
    }

    static func filterInFlightJobs(_ jobs: [PipelineJob]) -> [PipelineJob] {
        let activeStates: Set<JobState> = [.waiting, .transcribing, .diarizing, .generatingProtocol]
        return jobs.filter { activeStates.contains($0.state) }
    }

    // MARK: - Computed

    private var filteredSessions: [RecordingSession] {
        let base = Self.filterSessions(
            sessions,
            searchText: searchText,
            tag: selectedTag,
            folder: selectedFolder,
            startDate: filterStartDate,
            endDate: filterEndDate,
            fullTextIDs: fullTextSearchEnabled && !searchText.isEmpty ? fullTextMatches : nil
        )
        switch sortOrder {
        case .newestFirst: return base.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst: return base.sorted { $0.createdAt < $1.createdAt }
        case .longestFirst: return base.sorted { $0.duration > $1.duration }
        case .shortestFirst: return base.sorted { $0.duration < $1.duration }
        case .titleAZ: return base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    private var allTags: [String] {
        Array(Set(sessions.flatMap(\.tags))).sorted()
    }

    private var allFolders: [String] {
        Array(Set(sessions.compactMap { $0.folderGroup.isEmpty ? nil : $0.folderGroup })).sorted()
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

                if isMultiSelectMode {
                    Button("Cancel") {
                        isMultiSelectMode = false
                        multiSelection = []
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    if !multiSelection.isEmpty {
                        Button {
                            exportSelected()
                        } label: {
                            Label("Export \(multiSelection.count)", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else {
                    Button {
                        isMultiSelectMode = true
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Select multiple recordings")

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
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                HStack {
                    Image(systemName: isSearchingFullText ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                    TextField("Search…", text: $searchText)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, query in
                            if fullTextSearchEnabled && !query.isEmpty {
                                triggerFullTextSearch(query: query, outputDir: nil)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            fullTextMatches = []
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

                // Full-text search toggle
                Button {
                    fullTextSearchEnabled.toggle()
                    if fullTextSearchEnabled && !searchText.isEmpty {
                        triggerFullTextSearch(query: searchText, outputDir: nil)
                    } else {
                        fullTextMatches = []
                    }
                } label: {
                    Image(systemName: fullTextSearchEnabled ? "doc.text.magnifyingglass" : "doc.text")
                        .font(.system(size: 13))
                        .foregroundStyle(fullTextSearchEnabled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(fullTextSearchEnabled ? "Full-text search: ON" : "Full-text search: OFF")

                // Date filter toggle
                Button {
                    showDateFilter.toggle()
                } label: {
                    Image(systemName: filterStartDate != nil || filterEndDate != nil ? "calendar.badge.clock" : "calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(filterStartDate != nil || filterEndDate != nil ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Filter by date range")

                // Sort picker
                Picker("", selection: $sortOrder) {
                    ForEach(SessionSort.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 86)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, showDateFilter ? 4 : 8)

            // Date filter row
            if showDateFilter {
                HStack(spacing: 8) {
                    Text("From")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(
                        get: { filterStartDate ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())! },
                        set: { filterStartDate = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: 110)
                    Text("to")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(
                        get: { filterEndDate ?? Date() },
                        set: { filterEndDate = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: 110)
                    if filterStartDate != nil || filterEndDate != nil {
                        Button("Clear") {
                            filterStartDate = nil
                            filterEndDate = nil
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Tag + folder filter chips
            if !allTags.isEmpty || !allFolders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if !allFolders.isEmpty {
                            filterChip(
                                icon: "folder",
                                label: selectedFolder ?? "All Folders",
                                isActive: selectedFolder != nil
                            ) {
                                selectedFolder = nil
                            }
                            ForEach(allFolders, id: \.self) { folder in
                                if selectedFolder != folder {
                                    filterChip(icon: "folder.fill", label: folder, isActive: false) {
                                        selectedFolder = folder
                                    }
                                }
                            }
                        }
                        if !allTags.isEmpty {
                            ForEach(allTags, id: \.self) { tag in
                                filterChip(
                                    icon: "tag",
                                    label: tag,
                                    isActive: selectedTag == tag
                                ) {
                                    selectedTag = selectedTag == tag ? nil : tag
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

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
        HStack(spacing: 0) {
            if isMultiSelectMode {
                Button {
                    if multiSelection.contains(session.id) {
                        multiSelection.remove(session.id)
                    } else {
                        multiSelection.insert(session.id)
                    }
                } label: {
                    Image(systemName: multiSelection.contains(session.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(multiSelection.contains(session.id) ? Color.accentColor : Color.secondary)
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
            }

            SessionRowView(
                session: session,
                isSelected: selectedSessionID == session.id,
                onDelete: { onDeleteSession(session) },
                allTags: allTags,
                allFolders: allFolders,
                onRename: { newTitle in
                    session.title = newTitle
                    try? modelContext.save()
                    let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                    try? SessionMeta.updateFields(in: dir, title: newTitle)
                },
                onAddTag: { tag in
                    guard !session.tags.contains(tag) else { return }
                    session.tags.append(tag)
                    try? modelContext.save()
                    let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                    try? SessionMeta.updateFields(in: dir, tags: session.tags)
                },
                onSetFolder: { folder in
                    session.folderGroup = folder
                    try? modelContext.save()
                    let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                    try? SessionMeta.updateFields(in: dir, folderGroup: folder)
                }
            )
            .onTapGesture {
                if isMultiSelectMode {
                    if multiSelection.contains(session.id) {
                        multiSelection.remove(session.id)
                    } else {
                        multiSelection.insert(session.id)
                    }
                } else {
                    selectedSessionID = session.id
                }
            }
        }
        Divider().padding(.leading, isMultiSelectMode ? 52 : 60)
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
                    onDelete: { onDeleteSession(session) },
                    allTags: allTags,
                    allFolders: allFolders,
                    onRename: { newTitle in
                        session.title = newTitle
                        try? modelContext.save()
                        let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                        try? SessionMeta.updateFields(in: dir, title: newTitle)
                    },
                    onAddTag: { tag in
                        guard !session.tags.contains(tag) else { return }
                        session.tags.append(tag)
                        try? modelContext.save()
                        let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                        try? SessionMeta.updateFields(in: dir, tags: session.tags)
                    },
                    onSetFolder: { folder in
                        session.folderGroup = folder
                        try? modelContext.save()
                        let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                        try? SessionMeta.updateFields(in: dir, folderGroup: folder)
                    }
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

    // MARK: - Bulk export

    private func exportSelected() {
        let selected = sessions.filter { multiSelection.contains($0.id) }
        guard !selected.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let root = AppPaths.transcriberRoot
        let paths: [(id: UUID, folderPath: String)] = selected.map { (id: $0.id, folderPath: $0.folderPath) }
        Task {
            let exported = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                for item in paths {
                    let srcDir = root.appendingPathComponent(item.folderPath)
                    guard fm.fileExists(atPath: srcDir.path) else { continue }
                    let slug = item.folderPath.isEmpty ? item.id.uuidString : item.folderPath
                    let targetDir = dest.appendingPathComponent(slug)
                    try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    for name in ["transcript.txt", "protocol.md"] {
                        let src = srcDir.appendingPathComponent(name)
                        guard fm.fileExists(atPath: src.path) else { continue }
                        let dst = targetDir.appendingPathComponent(name)
                        if fm.fileExists(atPath: dst.path) {
                            try? fm.removeItem(at: dst)
                        }
                        try? fm.copyItem(at: src, to: dst)
                    }
                }
                return dest
            }.value
            NSWorkspace.shared.open(exported)
            isMultiSelectMode = false
            multiSelection = []
        }
    }

    // MARK: - Full-text search

    private func triggerFullTextSearch(query: String, outputDir: URL?) {
        guard !query.isEmpty else { fullTextMatches = []; return }
        isSearchingFullText = true
        // Capture value types only before leaving the main actor.
        let paths: [(id: UUID, folderPath: String)] = sessions.map { (id: $0.id, folderPath: $0.folderPath) }
        let root = outputDir ?? AppPaths.transcriberRoot
        let capturedQuery = query
        Task {
            let matches = await Task.detached(priority: .userInitiated) {
                var found = Set<UUID>()
                for item in paths {
                    let url = root
                        .appendingPathComponent(item.folderPath)
                        .appendingPathComponent("transcript.txt")
                    if let text = try? String(contentsOf: url, encoding: .utf8),
                       text.localizedCaseInsensitiveContains(capturedQuery) {
                        found.insert(item.id)
                    }
                }
                return found
            }.value
            guard searchText == capturedQuery else { return }
            fullTextMatches = matches
            isSearchingFullText = false
        }
    }

    // MARK: - Filter chip

    @ViewBuilder
    private func filterChip(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11))
                if isActive {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptySearchState: some View {
        let hasFilter = !searchText.isEmpty || selectedTag != nil || selectedFolder != nil
            || filterStartDate != nil || filterEndDate != nil
        return VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: hasFilter ? "magnifyingglass" : "tray")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            if hasFilter {
                Text("No results")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button("Clear filters") {
                    searchText = ""
                    selectedTag = nil
                    selectedFolder = nil
                    filterStartDate = nil
                    filterEndDate = nil
                    fullTextMatches = []
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else {
                Text("No recordings yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Recorded meetings will appear here after transcription.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}
