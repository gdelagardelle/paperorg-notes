import Foundation
import SwiftData

@MainActor
final class DeleteNoteUseCase {
    private let storageService: StorageService
    
    init(storageService: StorageService) {
        self.storageService = storageService
    }
    
    func deleteAudio(for note: Note, context: ModelContext) throws {
        storageService.deleteAudio(for: note.id)
        note.audioDeletedAt = .now
        note.updatedAt = .now
        try context.save()
    }
    
    func deleteNote(_ note: Note, context: ModelContext) throws {
        storageService.deleteAudio(for: note.id)
        for segment in note.segments {
            context.delete(segment)
        }
        for section in note.structuredSections {
            context.delete(section)
        }
        context.delete(note)
        try context.save()
    }
    
    func deleteAllNotes(_ notes: [Note], context: ModelContext) throws {
        for note in notes {
            try deleteNote(note, context: context)
        }
    }
}
