package com.paperorg.notes.auto

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSession.MediaItemsWithStartPosition
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import com.paperorg.notes.MainActivity
import com.paperorg.notes.PaperorgNotesApp
import com.paperorg.notes.R
import com.paperorg.notes.data.RecordingForegroundService
import com.paperorg.notes.data.RecordingState
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.DurationFormat
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.NoteStatus
import com.paperorg.notes.domain.OutputType
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Android Auto browses saved notes and can start one new note.
 * The new-note row records on the phone microphone. Pause ends the take and the
 * phone transcribes and emails it with the same settings as a recording made in the app.
 * The car's own microphone is not available to this app.
 */
@UnstableApi
class NotesMediaService : MediaLibraryService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var player: ExoPlayer? = null
    private var session: MediaLibrarySession? = null
    private var carHasTake = false
    private var startingTake = false
    private var recordTicket = 0

    override fun onCreate() {
        super.onCreate()
        val exoPlayer = ExoPlayer.Builder(this).build()
        exoPlayer.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) {
                if (events.contains(Player.EVENT_IS_PLAYING_CHANGED) || events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION)) {
                    handlePlayback()
                }
            }
        })
        player = exoPlayer
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        session = MediaLibrarySession.Builder(this, exoPlayer, LibraryCallback())
            .setSessionActivity(openApp)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onDestroy() {
        if (carHasTake || startingTake) {
            endTake()
        }
        session?.release()
        session = null
        player?.release()
        player = null
        scope.cancel()
        super.onDestroy()
    }

    private fun audioFile(noteId: String): File =
        PaperorgNotesApp.instance.recording.audioFile(noteId)

    private fun <T> future(block: suspend () -> T): ListenableFuture<T> {
        val pending = SettableFuture.create<T>()
        scope.launch {
            try {
                pending.set(block())
            } catch (error: Exception) {
                pending.setException(error)
            }
        }
        return pending
    }

    private inner class LibraryCallback : MediaLibrarySession.Callback {
        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(rootItem(), params))

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = future {
            if (parentId != AutoCatalog.ROOT_ID) {
                return@future LibraryResult.ofItemList(ImmutableList.of(), params)
            }
            val items = catalogItems()
            val from = (page * pageSize).coerceAtLeast(0)
            val slice = if (from >= items.size) emptyList() else items.drop(from).take(pageSize.coerceAtLeast(1))
            LibraryResult.ofItemList(ImmutableList.copyOf(slice), params)
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> = future {
            val item = catalogItems().find { it.mediaId == mediaId }
            if (item == null) {
                LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE)
            } else {
                LibraryResult.ofItem(item, null)
            }
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
        ): ListenableFuture<List<MediaItem>> = future {
            mediaItems.map { requested -> resolve(requested) }
        }

        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaItemsWithStartPosition> = future {
            val resolved = mediaItems.map { requested -> resolve(requested) }
            MediaItemsWithStartPosition(resolved, startIndex, startPositionMs)
        }
    }

    private fun handlePlayback() {
        val exo = player ?: return
        val itemIsNewNote = exo.currentMediaItem?.mediaId == AutoCatalog.NEW_NOTE_ID
        if (itemIsNewNote) {
            exo.volume = 0f
            exo.repeatMode = Player.REPEAT_MODE_ONE
        }
        when (AutoCatalog.playbackCommand(itemIsNewNote, exo.isPlaying, carHasTake)) {
            CarRecordCommand.Start -> beginTake()
            CarRecordCommand.Stop -> endTake()
            CarRecordCommand.Ignore -> Unit
        }
        if (!itemIsNewNote && !carHasTake) {
            exo.volume = 1f
            exo.repeatMode = Player.REPEAT_MODE_OFF
        }
    }

    private fun beginTake() {
        if (startingTake || carHasTake) return
        val app = PaperorgNotesApp.instance
        if (app.recording.state != RecordingState.Idle) {
            carHasTake = true
            if (app.recording.state == RecordingState.Paused) app.recording.resume()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            showMicFailure()
            return
        }
        startingTake = true
        val ticket = ++recordTicket
        scope.launch {
            val noteId = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            val settings = app.settings
            val note = Note(
                id = noteId,
                title = getString(R.string.note_untitled),
                createdAtMillis = now,
                updatedAtMillis = now,
                durationSeconds = 0.0,
                audioFileName = "$noteId.m4a",
                language = AppLanguage.fromCode(settings.defaultLanguage).code,
                outputType = OutputType.entries.find { it.code == settings.defaultOutputType }?.code
                    ?: OutputType.Meeting.code,
                status = NoteStatus.Draft.name.lowercase(),
            )
            try {
                app.notes.save(note)
                if (ticket != recordTicket) {
                    app.notes.delete(noteId)
                    return@launch
                }
                app.recording.start(noteId)
                RecordingForegroundService.start(this@NotesMediaService, null)
                carHasTake = true
            } catch (_: Exception) {
                app.notes.delete(noteId)
                if (app.recording.currentNoteId == noteId) app.recording.cancel()
                if (ticket == recordTicket) showMicFailure()
            } finally {
                if (ticket == recordTicket) startingTake = false
            }
        }
    }

    private fun endTake() {
        if (!carHasTake && !startingTake) return
        carHasTake = false
        startingTake = false
        recordTicket++
        player?.volume = 1f
        player?.repeatMode = Player.REPEAT_MODE_OFF
        startService(
            Intent(this, RecordingForegroundService::class.java)
                .setAction(RecordingForegroundService.ACTION_STOP),
        )
    }

    private fun showMicFailure() {
        val exo = player ?: return
        exo.playWhenReady = false
        exo.volume = 1f
        val failed = newNoteItem().buildUpon()
            .setMediaMetadata(
                newNoteItem().mediaMetadata.buildUpon()
                    .setTitle(getString(R.string.error_mic))
                    .build(),
            )
            .build()
        exo.setMediaItem(failed)
        exo.prepare()
    }

    private suspend fun catalogItems(): List<MediaItem> {
        val saved = playableNotes()
        val byId = saved.associate { it.first.id to mediaItem(it.first, it.second) }
        return AutoCatalog.rows(saved.map { it.first }) { byId.containsKey(it) }
            .map { id -> if (id == AutoCatalog.NEW_NOTE_ID) newNoteItem() else byId.getValue(id) }
    }

    private suspend fun resolve(requested: MediaItem): MediaItem {
        if (requested.mediaId == AutoCatalog.NEW_NOTE_ID) return newNoteItem()
        val match = playableNotes().find { it.first.id == requested.mediaId }
        return if (match == null) requested else mediaItem(match.first, match.second)
    }

    private fun newNoteItem(): MediaItem =
        MediaItem.Builder()
            .setMediaId(AutoCatalog.NEW_NOTE_ID)
            .setUri(Uri.fromFile(silenceFile()))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(getString(R.string.auto_new_note))
                    .setArtist("Paperorg Notes")
                    .setSubtitle(getString(R.string.record_status_recording))
                    .setIsPlayable(true)
                    .setIsBrowsable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                    .build(),
            )
            .build()

    private fun silenceFile(): File {
        val file = File(cacheDir, "auto-silence.wav")
        if (file.exists() && file.length() > 44) return file
        file.writeBytes(silenceWav())
        return file
    }

    /** One second of 16-bit mono PCM. The player loops it at volume 0 while the mic is open. */
    private fun silenceWav(): ByteArray {
        val sampleRate = 22050
        val dataSize = sampleRate * 2
        val bytes = ByteArray(44 + dataSize)
        fun text(offset: Int, value: String) {
            value.forEachIndexed { index, char -> bytes[offset + index] = char.code.toByte() }
        }
        fun le32(offset: Int, value: Int) {
            bytes[offset] = (value and 0xff).toByte()
            bytes[offset + 1] = (value shr 8 and 0xff).toByte()
            bytes[offset + 2] = (value shr 16 and 0xff).toByte()
            bytes[offset + 3] = (value shr 24 and 0xff).toByte()
        }
        fun le16(offset: Int, value: Int) {
            bytes[offset] = (value and 0xff).toByte()
            bytes[offset + 1] = (value shr 8 and 0xff).toByte()
        }
        text(0, "RIFF")
        le32(4, 36 + dataSize)
        text(8, "WAVE")
        text(12, "fmt ")
        le32(16, 16)
        le16(20, 1)
        le16(22, 1)
        le32(24, sampleRate)
        le32(28, sampleRate * 2)
        le16(32, 2)
        le16(34, 16)
        text(36, "data")
        le32(40, dataSize)
        return bytes
    }

    private suspend fun playableNotes(): List<Pair<Note, File>> {
        val notes = PaperorgNotesApp.instance.notes.list()
        return AutoCatalog.playable(notes) { id -> audioFile(id).let { it.exists() && it.length() > 0L } }
            .map { note -> note to audioFile(note.id) }
    }

    private fun rootItem(): MediaItem =
        MediaItem.Builder()
            .setMediaId(AutoCatalog.ROOT_ID)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle("Paperorg Notes")
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                    .build(),
            )
            .build()

    private fun mediaItem(note: Note, file: File): MediaItem =
        MediaItem.Builder()
            .setMediaId(note.id)
            .setUri(Uri.fromFile(file))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(note.title.ifBlank { "Untitled" })
                    .setArtist("Paperorg Notes")
                    .setSubtitle(DurationFormat.format(note.durationSeconds))
                    .setIsPlayable(true)
                    .setIsBrowsable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                    .build(),
            )
            .build()
}
