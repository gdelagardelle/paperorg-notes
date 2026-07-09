import Foundation
import SwiftData

@MainActor
final class DeleteNoteUseCase {
    private let storageService: StorageService
    
    init(storageService: StorageService) {
        self.storageService = storageService
    }
    
    func deleteAudio(for note: Note, context: ModelContext) {
        storageService.deleteAudio(for: note.id)
        note.audioDeletedAt = .now
        note.updatedAt = .now
        try? context.save()
    }
    
    func deleteNote(_ note: Note, context: ModelContext) {
        storageService.deleteAudio(for: note.id)
        context.delete(note)
        try? context.save()
    }
    
    func deleteAllNotes(_ notes: [Note], context: ModelContext) {
        for note in notes {
            storageService.deleteAudio(for: note.id)
            context.delete(note)
        }
        try? context.save()
    }
}
