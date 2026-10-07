import AppKit
import SwiftData
import SwiftUI

enum MacSection: Hashable {
    case record
    case notes
    case tasks
    case decisions
    case clients
    case search
    case settings
}

struct MacMainView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: MacSection? = .record

    var body: some View {
        @Bindable var deepLink = environment.deepLinkHandler
        let recording = environment.recordingService

        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Record", systemImage: "mic.fill")
                        .tag(MacSection.record)
                    Label("Notes", systemImage: "doc.text.fill")
                        .tag(MacSection.notes)
                    Label("Tasks", systemImage: "checklist")
                        .tag(MacSection.tasks)
                    Label("Decisions", systemImage: "checkmark.seal")
                        .tag(MacSection.decisions)
                    Label("Clients", systemImage: "folder")
                        .tag(MacSection.clients)
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(MacSection.search)
                }
                Section {
                    Label("Settings", systemImage: "gearshape.fill")
                        .tag(MacSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    AppBuildBadge()
                }
            }
        } detail: {
            Group {
                switch selection ?? .record {
                case .record:
                    RecordView()
                case .notes:
                    NotesListView()
                case .tasks:
                    TasksInboxView()
                case .decisions:
                    DecisionsBoardView()
                case .clients:
                    ClientDossiersView()
                case .search:
                    SearchView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppScreenBackground())
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.accent)
        .safeAreaInset(edge: .top, spacing: 0) {
            if recording.state != .idle {
                RecordingInProgressBanner(
                    state: recording.state,
                    duration: recording.duration,
                    onOpenRecordTab: { selection = .record }
                )
            }
        }
        .onAppear {
            syncSelection(with: deepLink.selectedTab)
        }
        .onChange(of: deepLink.selectedTab) { _, tab in
            syncSelection(with: tab)
        }
        .onChange(of: selection) { _, section in
            guard let section, section == .record || section == .notes || section == .search || section == .settings else { return }
            deepLink.selectedTab = macTabIndex(for: section)
        }
        .onChange(of: deepLink.requestedMacSection) { _, section in
            guard section == "tasks" else { return }
            selection = .tasks
            deepLink.requestedMacSection = nil
        }
    }

    private func syncSelection(with tab: Int) {
        switch tab {
        case 0: selection = .record
        case 1: selection = .notes
        case 2: selection = .search
        case 3: selection = .settings
        default: break
        }
    }

    private func macTabIndex(for section: MacSection) -> Int {
        switch section {
        case .record: 0
        case .notes: 1
        case .search: 2
        case .settings: 3
        case .tasks, .decisions, .clients: 1
        }
    }
}

struct MacMenuBarPopover: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settingsService

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("Paperorg Notes")
                    .font(.headline)
                Spacer()
                MenuBarOpenTaskCount()
            }

            OutputTypePicker(selection: $settings.defaultOutputType, label: "Output type", style: .menu)

            MacQuickRecordControls()

            Divider()

            Button("Open Library…") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Button("Tasks") {
                environment.deepLinkHandler.requestedMacSection = "tasks"
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

struct MacQuickRecordControls: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @State private var isProcessing = false

    var body: some View {
        let recording = environment.recordingService

        VStack(spacing: 10) {
            Text(DurationFormatter.format(recording.duration))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)

            HStack {
                if recording.state == .idle {
                    Button("Record") {
                        Task { await startRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                } else if recording.state == .recording {
                    Button("Pause") {
                        environment.recordingService.pause()
                    }
                    Button("Stop") {
                        Task { await stopRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if recording.state == .paused {
                    Button("Resume") {
                        environment.recordingService.resume()
                    }
                    Button("Stop") {
                        Task { await stopRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .disabled(isProcessing)
    }

    private func startRecording() async {
        let noteId = UUID()
        do {
            try await environment.recordingService.start(
                noteId: noteId,
                maxRecordingMinutes: RecordingLengthPolicy.capMinutes(
                    from: environment.settingsService.cachedProUsage,
                    isPro: environment.subscriptionService.isProActive
                )
            )
            let note = Note(
                id: noteId,
                audioFileName: "\(noteId.uuidString).m4a",
                language: environment.settingsService.defaultLanguage,
                outputType: environment.settingsService.defaultOutputType,
                status: .draft
            )
            modelContext.insert(note)
            try modelContext.save()
        } catch {
            print("Menu bar record failed: \(error.localizedDescription)")
        }
    }

    private func stopRecording() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await environment.recordingService.stop()
            let targetId = result.noteId
            guard let note = try? modelContext.fetch(FetchDescriptor<Note>(
                predicate: #Predicate { $0.id == targetId }
            )).first else { return }
            note.audioFileName = result.audioURL.lastPathComponent
            note.durationSeconds = result.duration
            note.status = NoteStatus.processing.rawValue
            note.updatedAt = .now
            try modelContext.save()
            try await environment.processRecordingUseCase.execute(
                note: note,
                audioURL: result.audioURL
            ) { _ in }
            try modelContext.save()
        } catch {
            print("Menu bar stop failed: \(error.localizedDescription)")
        }
    }
}

struct MenuBarOpenTaskCount: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    private var count: Int {
        let mine = environment.settingsService.deskUserName
        return OfficeWorkflow.openTasks(in: notes).filter { row in
            if mine.isEmpty {
                return row.item.assignee == nil
            }
            return row.item.assignee?.caseInsensitiveCompare(mine) == .orderedSame
        }.count
    }

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.accent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }
}

struct AttachedModelContainer: ViewModifier {
    let result: Result<ModelContainer, Error>

    func body(content: Content) -> some View {
        if case .success(let container) = result {
            content.modelContainer(container)
        } else {
            content
        }
    }
}
