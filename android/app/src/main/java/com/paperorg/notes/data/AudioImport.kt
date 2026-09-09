package com.paperorg.notes.data

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import com.paperorg.notes.domain.AudioFormat
import com.paperorg.notes.domain.ImportPolicy
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Brings an existing audio file into a note's own storage slot.
 *
 * The file is kept in the container it arrived in rather than transcoded. The
 * API reads duration from the bytes and accepts MP3, WAV and M4A directly, so
 * re-encoding would cost quality and battery for nothing.
 */
class AudioImport(
    private val context: Context,
    private val recording: RecordingController,
) {
    data class Imported(val file: File, val seconds: Double, val format: AudioFormat)

    /**
     * Copies [uri] in as the audio for [noteId].
     *
     * Duration and size are checked against the picked document before anything
     * is copied, so a file that cannot be sent costs nothing but the check.
     */
    suspend fun import(uri: Uri, noteId: String, maxRecordingMinutes: Int?): Imported =
        withContext(Dispatchers.IO) {
            val document = describe(uri)
            val format = AudioFormat.forImport(document.mimeType, document.name)
                ?: error("Paperorg Notes can import MP3, WAV and M4A files.")

            val seconds = durationSeconds(uri)
                ?: error("This file could not be read as audio.")
            ImportPolicy.refusal(seconds, document.bytes, maxRecordingMinutes)?.let { error(it) }

            val destination = File(recording.recordingsDir, "$noteId.${format.extension}")
            // A note keeps one audio file; an earlier import in another container
            // would otherwise still be found first when the note is played.
            recording.deleteAudio(noteId)
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    destination.outputStream().use(input::copyTo)
                } ?: error("This file could not be opened.")
            } catch (error: Exception) {
                destination.delete()
                throw error
            }
            if (destination.length() == 0L) {
                destination.delete()
                error("This file could not be read as audio.")
            }
            Imported(destination, seconds, format)
        }

    private data class Document(val name: String?, val mimeType: String?, val bytes: Long)

    private fun describe(uri: Uri): Document {
        val mimeType = context.contentResolver.getType(uri)
        var name: String? = null
        var bytes = 0L
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    .takeIf { it >= 0 && !cursor.isNull(it) }
                    ?.let { name = cursor.getString(it) }
                cursor.getColumnIndex(OpenableColumns.SIZE)
                    .takeIf { it >= 0 && !cursor.isNull(it) }
                    ?.let { bytes = cursor.getLong(it) }
            }
        }
        return Document(name ?: uri.lastPathSegment, mimeType, bytes)
    }

    /** Null when the file is not decodable audio, which is a refusal not a zero. */
    private fun durationSeconds(uri: Uri): Double? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?.takeIf { it > 0 }
                ?.let { it / 1000.0 }
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }
}
