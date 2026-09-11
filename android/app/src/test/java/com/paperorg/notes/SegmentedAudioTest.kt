package com.paperorg.notes

import com.paperorg.notes.data.SegmentedAudio
import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class SegmentedAudioTest {
    private fun directory() = Files.createTempDirectory("segments-test").toFile().also { it.deleteOnExit() }

    @Test fun rotationPreservesEverySampleAndFullPlaybackOrder() {
        val dir = directory()
        val store = SegmentedAudio(dir, segmentBytes = 8)
        val source = ByteArray(22) { it.toByte() }
        store.append(source, source.size)
        assertEquals(listOf(0, 1), store.segments().map { it.index })
        store.finish()
        assertEquals(listOf(8L, 8L, 6L), store.segments().map { it.file.length() - 44 })
        val full = File(dir, "full.wav")
        store.assemble(full)
        assertArrayEquals(source, full.readBytes().drop(44).toByteArray())
        assertEquals(22.0 / 32000, store.durationSeconds(), 0.00001)
    }

    @Test fun interruptedOpenSegmentIsRecoveredAndHeaderRepaired() {
        val dir = directory()
        val store = SegmentedAudio(dir, segmentBytes = 8)
        store.append(byteArrayOf(1, 2, 3, 4, 5, 6), 6)
        val recovered = SegmentedAudio(dir, segmentBytes = 8)
        recovered.recover()
        assertEquals(1, recovered.segments().size)
        val bytes = recovered.segments().single().file.readBytes()
        assertEquals(6, bytes[40].toInt())
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6), bytes.drop(44).toByteArray())
        store.finish()
    }

    @Test fun completedResultsAreDurableOrderedAndNotSubmittedAgain() {
        val dir = directory()
        val store = SegmentedAudio(dir, segmentBytes = 8)
        store.append(ByteArray(16), 16)
        store.finish()
        store.saveTranscript(1, "second", "openai")
        store.saveTranscript(0, "first", "openai")
        val reopened = SegmentedAudio(dir)
        assertEquals("first\n\nsecond", reopened.combinedTranscript())
        assertTrue(reopened.pending().isEmpty())
    }

    @Test fun emptyRecordingNeverPublishesAnEmptySegment() {
        val store = SegmentedAudio(directory())
        store.finish()
        assertTrue(store.segments().isEmpty())
    }

    @Test fun failedQueueRetainsProgressAndRetryOnlyRequestsMissingChunks() {
        val dir = directory()
        val store = SegmentedAudio(dir, segmentBytes = 8)
        store.append(ByteArray(24), 24)
        store.finish()
        assertThrows(java.io.IOException::class.java) {
            store.transcribePending { part ->
                if (part.index == 1) throw java.io.IOException("offline")
                "first" to "openai"
            }
        }
        assertEquals(listOf(1, 2), SegmentedAudio(dir).pending().map { it.index })
        val requested = mutableListOf<Int>()
        SegmentedAudio(dir).transcribePending { part -> requested.add(part.index); "part ${part.index}" to "openai" }
        assertEquals(listOf(1, 2), requested)
        assertEquals("first\n\npart 1\n\npart 2", SegmentedAudio(dir).combinedTranscript())
    }

}
