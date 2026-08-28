package com.paperorg.notes.data.db

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.Update
import com.paperorg.notes.domain.Note
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Entity(tableName = "notes")
data class NoteEntity(
    @PrimaryKey val id: String,
    val title: String,
    val createdAtMillis: Long,
    val updatedAtMillis: Long,
    val durationSeconds: Double,
    val audioFileName: String,
    val language: String,
    val outputType: String,
    val status: String,
    val processingStage: String?,
    val isFavorite: Boolean,
    val projectName: String?,
    val rawTranscript: String?,
    val summaryShort: String?,
    val summaryDetailed: String?,
    val structuredJson: String?,
    val primaryProvider: String?,
    val errorMessage: String?,
    val tags: String,
)

fun NoteEntity.toNote() = Note(
    id, title, createdAtMillis, updatedAtMillis, durationSeconds, audioFileName,
    language, outputType, status, processingStage, isFavorite, projectName,
    rawTranscript, summaryShort, summaryDetailed, structuredJson, primaryProvider,
    errorMessage, tags,
)

fun Note.toEntity() = NoteEntity(
    id, title, createdAtMillis, updatedAtMillis, durationSeconds, audioFileName,
    language, outputType, status, processingStage, isFavorite, projectName,
    rawTranscript, summaryShort, summaryDetailed, structuredJson, primaryProvider,
    errorMessage, tags,
)

@Dao
interface NoteDao {
    @Query("SELECT * FROM notes ORDER BY createdAtMillis DESC")
    fun observeAll(): Flow<List<NoteEntity>>

    @Query("SELECT * FROM notes WHERE id = :id")
    suspend fun get(id: String): NoteEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(note: NoteEntity)

    @Update
    suspend fun update(note: NoteEntity)

    @Query("DELETE FROM notes WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM notes")
    suspend fun deleteAll()
}

@Database(entities = [NoteEntity::class], version = 1, exportSchema = false)
abstract class NotesDatabase : RoomDatabase() {
    abstract fun notes(): NoteDao
}

class NotesRepository(private val dao: NoteDao) {
    fun observeNotes(): Flow<List<Note>> = dao.observeAll().map { rows -> rows.map { it.toNote() } }
    suspend fun get(id: String): Note? = dao.get(id)?.toNote()
    suspend fun save(note: Note) = dao.upsert(note.toEntity())
    suspend fun delete(id: String) = dao.delete(id)
    suspend fun deleteAll() = dao.deleteAll()
}
