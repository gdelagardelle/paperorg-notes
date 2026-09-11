package com.paperorg.notes

import com.paperorg.notes.data.ContinuousCapture
import com.paperorg.notes.data.PcmMicrophone
import com.paperorg.notes.data.SegmentedAudio
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class ContinuousCaptureTest {
    @Test fun stopUnblocksAWaitingMicrophoneAndReleasesItOnce() {
        val store = SegmentedAudio(Files.createTempDirectory("capture-stop").toFile(), 8)
        val reading = java.util.concurrent.CountDownLatch(1)
        val stopped = java.util.concurrent.CountDownLatch(1)
        var stops = 0
        val mic = object : PcmMicrophone {
            override fun start() = Unit
            override fun read(buffer: ByteArray): Int { reading.countDown(); stopped.await(2, java.util.concurrent.TimeUnit.SECONDS); return -3 }
            override fun stop() { stops++; stopped.countDown() }
        }
        val capture = ContinuousCapture(mic, store, 60.0, { true })
        val thread = Thread { runCatching { capture.run() } }.also { it.start() }
        assertTrue(reading.await(1, java.util.concurrent.TimeUnit.SECONDS))
        capture.requestStop()
        thread.join(500)
        assertFalse(thread.isAlive)
        assertEquals(1, stops)
    }
    @Test fun oneMicrophoneSessionSpansRotationsAndStopsExactlyAtTotalCap() {
        val store = SegmentedAudio(Files.createTempDirectory("capture").toFile(), 8)
        val mic = CountingMicrophone()
        val capture = ContinuousCapture(mic, store, maxSeconds = 20.0 / 32000, hasSpace = { true })
        capture.run()
        assertEquals(1, mic.starts)
        assertEquals(1, mic.stops)
        assertEquals(listOf(8L, 8L, 4L), store.segments().map { it.file.length() - 44 })
    }

    @Test fun lowDiskStopsAndPreservesAlreadyCapturedAudio() {
        val store = SegmentedAudio(Files.createTempDirectory("capture").toFile(), 8)
        val mic = CountingMicrophone()
        var checks = 0
        val capture = ContinuousCapture(mic, store, maxSeconds = 60.0, hasSpace = { checks++ < 1 })
        assertThrows(IllegalStateException::class.java) { capture.run() }
        assertEquals(8L, store.segments().sumOf { it.file.length() - 44 })
        assertEquals(1, mic.stops)
    }

    private class CountingMicrophone : PcmMicrophone {
        var starts = 0
        var stops = 0
        override fun start() { starts++ }
        override fun read(buffer: ByteArray): Int { buffer.fill(1, 0, 8); return 8 }
        override fun stop() { stops++ }
    }
}
