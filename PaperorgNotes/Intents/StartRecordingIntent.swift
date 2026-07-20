import AppIntents
import Foundation

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start a new voice note in Paperorg Notes.")
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Language")
    var language: RecordingLanguageEntity?
    
    @Parameter(title: "Note Style")
    var noteStyle: NoteStyleEntity?
    
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord)
        defaults.set(Date().timeIntervalSince1970, forKey: AppConstants.UserDefaultsKeys.quickRecordRequestedAt)
        if let language {
            defaults.set(language.id, forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
        } else {
            defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
        }
        if let noteStyle {
            defaults.set(noteStyle.id, forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
        } else {
            defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
        }
        return .result()
    }
}

struct PaperorgNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Record a note with \(.applicationName)",
                "New voice note in \(.applicationName)"
            ],
            shortTitle: "Record",
            systemImageName: "mic.fill"
        )
    }
}

struct RecordingLanguageEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Language")
    static var defaultQuery = RecordingLanguageQuery()
    
    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct RecordingLanguageQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RecordingLanguageEntity] {
        identifiers.map { RecordingLanguageEntity(id: $0) }
    }
    
    func suggestedEntities() async throws -> [RecordingLanguageEntity] {
        AppLanguage.allCases.map { RecordingLanguageEntity(id: $0.rawValue) }
    }
}

struct NoteStyleEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note Style")
    static var defaultQuery = NoteStyleQuery()
    
    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct NoteStyleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NoteStyleEntity] {
        identifiers.map { NoteStyleEntity(id: $0) }
    }
    
    func suggestedEntities() async throws -> [NoteStyleEntity] {
        OutputType.allCases.map { NoteStyleEntity(id: $0.rawValue) }
    }
}
