package com.paperorg.notes.data

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.AudioRecord
import android.media.AudioFormat as AndroidAudioFormat
import com.paperorg.notes.domain.AudioFormat
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class RecordingState { Idle, Recording, Paused }

class RecordingController(private val context: Context) {
    @Volatile var state: RecordingState = RecordingState.Idle
        private set
    @Volatile var currentNoteId: String? = null
        private set
    var startedAtMillis: Long = 0
        private set
    var pausedAccumulatedMillis: Long = 0
        private set
    var pauseStartedAt: Long = 0
        private set

    private var capture: ContinuousCapture? = null
    private var captureThread: Thread? = null
    @Volatile var captureError: String? = null
        private set
    @Volatile var captureFinished = false
        private set
    var onSegmentReady: ((String) -> Unit)? = null
    private var player: MediaPlayer? = null
    @Volatile private var activeAudio: SegmentedAudio? = null

    fun segmentDirectory(noteId: String) = File(recordingsDir, "$noteId.segments")
    fun segments(noteId: String): SegmentedAudio? =
        if (currentNoteId == noteId) activeAudio else segmentDirectory(noteId).takeIf { it.isDirectory }?.let { SegmentedAudio(it) }

    fun recoverInterrupted(): List<String> = recordingsDir.listFiles().orEmpty()
        .filter { it.isDirectory && it.name.endsWith(".segments") }.map { directory ->
            SegmentedAudio(directory).recover()
            directory.name.removeSuffix(".segments")
        }

    val recordingsDir: File
        get() = File(context.filesDir, "recordings").also { it.mkdirs() }

    /**
     * The audio for [noteId], whichever container it is in.
     *
     * New recordings are WAV; legacy recordings and imports keep their container.
     * The legacy M4A fallback remains for callers creating an import destination.
     */
    fun audioFile(noteId: String): File =
        AudioFormat.entries
            .map { File(recordingsDir, "$noteId.${it.extension}") }
            .firstOrNull { it.exists() }
            ?: File(recordingsDir, "$noteId.${AudioFormat.M4A.extension}")

    fun durationSeconds(): Double {
        if (state == RecordingState.Idle) return 0.0
        return activeAudio?.durationSeconds() ?: 0.0
    }

    fun start(noteId: String, maxSeconds: Double = 180.0) {
        if (state != RecordingState.Idle) error("Already recording.")
        require(maxSeconds > 0) { "Your recording allowance has been used. Audio already saved remains available." }
        check(recordingsDir.usableSpace > 64L * 1024 * 1024) { "Free some storage before recording." }
        val minimum = AudioRecord.getMinBufferSize(16000, AndroidAudioFormat.CHANNEL_IN_MONO, AndroidAudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Microphone format is unavailable." }
        val audio = SegmentedAudio(segmentDirectory(noteId))
        val microphone = AudioRecord(MediaRecorder.AudioSource.MIC, 16000,
            AndroidAudioFormat.CHANNEL_IN_MONO, AndroidAudioFormat.ENCODING_PCM_16BIT, maxOf(minimum * 4, 32000))
        try {
            check(microphone.state == AudioRecord.STATE_INITIALIZED)
            microphone.startRecording()
            check(microphone.recordingState == AudioRecord.RECORDSTATE_RECORDING)
        } catch (error: Exception) {
            microphone.release()
            throw IllegalStateException(
                "Could not start the microphone. Grant the microphone permission and try again.",
                error,
            )
        }
        activeAudio = audio
        currentNoteId = noteId
        startedAtMillis = System.currentTimeMillis()
        pausedAccumulatedMillis = 0
        pauseStartedAt = 0
        state = RecordingState.Recording
        captureError = null
        captureFinished = false
        val pump = ContinuousCapture(object : PcmMicrophone {
            override fun start() = Unit // Already started synchronously so permission errors reach the UI.
            override fun read(buffer: ByteArray) = microphone.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
            override fun stop() { try { microphone.stop() } finally { microphone.release() } }
        }, audio, maxSeconds, {
            // Reserve enough for the complete playback/export file plus a small safety margin.
            recordingsDir.usableSpace > (audio.durationSeconds() * 32000).toLong() + 32L * 1024 * 1024
        }, { runCatching { onSegmentReady?.invoke(noteId) }; Unit })
        capture = pump
        captureThread = Thread({
            try { pump.run() } catch (error: Exception) { captureError = error.message }
            finally { captureFinished = true }
        }, "paperorg-microphone").also { it.start() }
    }

    fun pause() {
        if (state != RecordingState.Recording) return
        capture?.paused = true
        pauseStartedAt = System.currentTimeMillis()
        state = RecordingState.Paused
    }

    fun resume() {
        if (state != RecordingState.Paused) return
        capture?.paused = false
        if (pauseStartedAt > 0) {
            pausedAccumulatedMillis += System.currentTimeMillis() - pauseStartedAt
            pauseStartedAt = 0
        }
        state = RecordingState.Recording
    }

    @Synchronized
    fun stop(): File? {
        val noteId = currentNoteId ?: return null
        capture?.requestStop()
        captureThread?.join(2000)
        check(captureThread?.isAlive != true) { "The microphone is still stopping. Your audio is safe; try Stop again." }
        capture = null
        captureThread = null
        val dest = File(recordingsDir, "$noteId.wav")
        // Do not assemble here on the UI thread; processing/export assembles on IO.
        currentNoteId = null
        state = RecordingState.Idle
        return dest
    }

    fun cancel() {
        val noteId = currentNoteId
        capture?.requestStop()
        captureThread?.join(2000)
        check(captureThread?.isAlive != true) { "The microphone is still stopping. Your audio has not been deleted." }
        capture = null
        captureThread = null
        noteId?.let { segmentDirectory(it).deleteRecursively() }
        activeAudio = null
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
        segmentDirectory(noteId).deleteRecursively()
        File(recordingsDir, "$noteId.wav.assembling").delete()
    }

    fun deleteAllAudio() {
        recordingsDir.listFiles()?.forEach { it.deleteRecursively() }
    }
}
