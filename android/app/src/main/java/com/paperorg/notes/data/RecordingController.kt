package com.paperorg.notes.data

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import com.paperorg.notes.domain.AudioFormat
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class RecordingState { Idle, Recording, Paused }

class RecordingController(private val context: Context) {
    var state: RecordingState = RecordingState.Idle
        private set
    var currentNoteId: String? = null
        private set
    var startedAtMillis: Long = 0
        private set
    var pausedAccumulatedMillis: Long = 0
        private set
    var pauseStartedAt: Long = 0
        private set

    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null
    private var tempFile: File? = null

    val recordingsDir: File
        get() = File(context.filesDir, "recordings").also { it.mkdirs() }

    /**
     * The audio for [noteId], whichever container it is in.
     *
     * Recordings are always M4A, but an import keeps the container it arrived in,
     * so the extension cannot be assumed. The M4A path is returned when nothing
     * exists yet, because that is what a new recording will write.
     */
    fun audioFile(noteId: String): File =
        AudioFormat.entries
            .map { File(recordingsDir, "$noteId.${it.extension}") }
            .firstOrNull { it.exists() }
            ?: File(recordingsDir, "$noteId.${AudioFormat.M4A.extension}")

    fun durationSeconds(): Double {
        if (state == RecordingState.Idle) return 0.0
        val now = System.currentTimeMillis()
        val paused = pausedAccumulatedMillis + if (state == RecordingState.Paused && pauseStartedAt > 0) {
            now - pauseStartedAt
        } else {
            0
        }
        return ((now - startedAtMillis - paused).coerceAtLeast(0) / 1000.0)
    }

    fun start(noteId: String) {
        if (state != RecordingState.Idle) error("Already recording.")
        val file = File(recordingsDir, "temp-${UUID.randomUUID()}.m4a")
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        try {
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioSamplingRate(44100)
            mediaRecorder.setAudioChannels(1)
            mediaRecorder.setAudioEncodingBitRate(128000)
            mediaRecorder.setOutputFile(file.absolutePath)
            mediaRecorder.prepare()
            mediaRecorder.start()
        } catch (error: Exception) {
            mediaRecorder.release()
            file.delete()
            throw IllegalStateException(
                "Could not start the microphone. Grant the microphone permission and try again.",
                error,
            )
        }
        recorder = mediaRecorder
        tempFile = file
        currentNoteId = noteId
        startedAtMillis = System.currentTimeMillis()
        pausedAccumulatedMillis = 0
        pauseStartedAt = 0
        state = RecordingState.Recording
    }

    fun pause() {
        if (state != RecordingState.Recording) return
        recorder?.pause()
        pauseStartedAt = System.currentTimeMillis()
        state = RecordingState.Paused
    }

    fun resume() {
        if (state != RecordingState.Paused) return
        recorder?.resume()
        if (pauseStartedAt > 0) {
            pausedAccumulatedMillis += System.currentTimeMillis() - pauseStartedAt
            pauseStartedAt = 0
        }
        state = RecordingState.Recording
    }

    fun stop(): File {
        val noteId = currentNoteId ?: error("No recording.")
        try {
            recorder?.stop()
        } catch (_: RuntimeException) {
            // A too-short tap can throw; keep the file if it exists.
        }
        recorder?.release()
        recorder = null
        val source = tempFile ?: error("No temp file.")
        val dest = audioFile(noteId)
        if (dest.exists()) dest.delete()
        source.copyTo(dest, overwrite = true)
        source.delete()
        tempFile = null
        currentNoteId = null
        state = RecordingState.Idle
        return dest
    }

    fun cancel() {
        try {
            recorder?.stop()
        } catch (_: RuntimeException) {
        }
        recorder?.release()
        recorder = null
        tempFile?.delete()
        tempFile = null
        currentNoteId = null
        state = RecordingState.Idle
    }

    fun hasAudio(noteId: String): Boolean = audioFile(noteId).exists()

    fun play(noteId: String, onComplete: () -> Unit) {
        stopPlayback()
        val file = audioFile(noteId)
        if (!file.exists()) error("The audio is no longer on this device.")
        val mediaPlayer = MediaPlayer()
        try {
            mediaPlayer.setDataSource(file.absolutePath)
            mediaPlayer.setOnCompletionListener {
                onComplete()
                stopPlayback()
            }
            mediaPlayer.prepare()
            mediaPlayer.start()
            player = mediaPlayer
        } catch (error: Exception) {
            mediaPlayer.release()
            throw IllegalStateException("Could not play the recording.", error)
        }
    }

    fun stopPlayback() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null
    }

    suspend fun deleteAudio(noteId: String) = withContext(Dispatchers.IO) {
        // Every container, not just the one audioFile would resolve to, so a
        // deletion cannot leave a second copy behind for the next lookup to find.
        AudioFormat.entries.forEach { File(recordingsDir, "$noteId.${it.extension}").delete() }
    }

    fun deleteAllAudio() {
        recordingsDir.listFiles()?.forEach { it.delete() }
    }
}
