package com.paperorg.notes.data

import android.content.Context
import com.paperorg.notes.domain.Note
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GdprExport(
    private val context: Context,
    private val recording: RecordingController,
) {
    fun export(notes: List<Note>): File {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val out = File(context.cacheDir, "paperorg-notes-export-$stamp.zip")
        ZipOutputStream(out.outputStream()).use { zip ->
            notes.forEach { note ->
                val body = buildString {
                    appendLine("Title: ${note.title}")
                    appendLine("Created: ${Date(note.createdAtMillis)}")
                    appendLine("Language: ${note.language}")
                    appendLine("Output: ${note.outputType}")
                    appendLine()
                    appendLine("Summary")
                    appendLine(note.summaryShort.orEmpty())
                    appendLine()
                    appendLine("Transcript")
                    appendLine(note.rawTranscript.orEmpty())
                }
                zip.putNextEntry(ZipEntry("notes/${note.id}.txt"))
                zip.write(body.toByteArray())
                zip.closeEntry()
                val audio = recording.audioFile(note.id)
                if (audio.exists()) {
                    zip.putNextEntry(ZipEntry("audio/${audio.name}"))
                    audio.inputStream().use { it.copyTo(zip) }
                    zip.closeEntry()
                }
            }
        }
        return out
    }
}
