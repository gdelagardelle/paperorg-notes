package com.paperorg.notes.data

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject

class SegmentedAudio(private val directory: File, private val segmentBytes: Int = 120 * 32000) {
    data class Segment(val index: Int, val file: File, val startSeconds: Double = 0.0) {
        val durationSeconds: Double get() = (file.length() - 44).coerceAtLeast(0) / 32000.0
    }
    private var output: RandomAccessFile? = null
    private var openFile: File? = null
    private var payloadBytes = 0
    private var nextIndex = 0
    init {
        require(segmentBytes > 0 && segmentBytes % 2 == 0)
        directory.mkdirs()
        nextIndex = (segments().maxOfOrNull { it.index } ?: -1) + 1
    }

    @Synchronized fun append(bytes: ByteArray, count: Int) {
        require(count in 0..bytes.size && count % 2 == 0)
        var offset = 0
        while (offset < count) {
            if (output == null) {
                openFile = File(directory, "%06d.open".format(nextIndex++))
                output = RandomAccessFile(openFile, "rw").also { it.write(header(0)) }
                payloadBytes = 0
            }
            val length = minOf(count - offset, segmentBytes - payloadBytes)
            output!!.write(bytes, offset, length)
            payloadBytes += length
            offset += length
            output!!.fd.sync()
            if (payloadBytes == segmentBytes) seal()
        }
    }

    private fun seal() {
        val file = openFile ?: return
        output?.let { it.seek(0); it.write(header(payloadBytes)); it.fd.sync(); it.close() }
        output = null
        if (file.exists()) {
            check(file.renameTo(File(directory, file.nameWithoutExtension + ".wav"))) { "Could not save audio segment." }
        }
        openFile = null
        payloadBytes = 0
    }

    @Synchronized fun finish() { seal(); atomicWrite(File(directory, "finished"), byteArrayOf(1)) }

    /** Called only on process startup, when no capture thread owns these files. */
    @Synchronized fun recover() {
        directory.listFiles()?.filter { it.extension == "open" }?.forEach { file ->
            val size = ((file.length() - 44).coerceAtLeast(0) / 2 * 2).toInt()
            if (size == 0) file.delete() else {
                RandomAccessFile(file, "rw").use { it.setLength(44L + size); it.seek(0); it.write(header(size)); it.fd.sync() }
                check(file.renameTo(File(directory, file.nameWithoutExtension + ".wav")))
            }
        }
        finish()
    }

    @Synchronized fun segments(): List<Segment> {
        var start = 0.0
        return directory.listFiles().orEmpty().filter { it.extension == "wav" && it.nameWithoutExtension.toIntOrNull() != null }
            .sortedBy { it.name }.map { file ->
                Segment(file.nameWithoutExtension.toInt(), file, start).also { start += it.durationSeconds }
            }
    }

    @Synchronized fun assemble(destination: File) {
        val parts = segments()
        val total = parts.sumOf { it.file.length() - 44 }
        require(total <= Int.MAX_VALUE - 44) { "Recording is too large to export." }
        val temporary = File(destination.parentFile, destination.name + ".assembling")
        RandomAccessFile(temporary, "rw").use { full ->
            full.setLength(0)
            full.write(header(total.toInt()))
            val buffer = ByteArray(65536)
            parts.forEach { part ->
                RandomAccessFile(part.file, "r").use { input ->
                    input.seek(44)
                    while (true) { val n = input.read(buffer); if (n < 0) break; full.write(buffer, 0, n) }
                }
            }
            full.fd.sync()
        }
        check(temporary.renameTo(destination)) { "Could not save complete recording." }
    }

    @Synchronized fun durationSeconds(): Double = segments().sumOf { it.durationSeconds } + payloadBytes / 32000.0
    @Synchronized fun saveTranscript(index: Int, text: String, provider: String) {
        require(segments().any { it.index == index })
        atomicWrite(File(directory, "%06d.json".format(index)), JSONObject().put("text", text).put("provider", provider).toString().toByteArray())
    }
    @Synchronized fun combinedTranscript(): String = segments().mapNotNull { segment ->
        transcript(segment.index)?.optString("text")?.takeIf { it.isNotBlank() }
    }.joinToString("\n\n")
    @Synchronized fun pending(): List<Segment> = segments().filter { transcript(it.index) == null }
    /** Caller serializes queue consumers; never hold the capture lock across a network request. */
    fun transcribePending(transcribe: (Segment) -> Pair<String, String>) {
        pending().forEach { segment ->
            val (text, provider) = transcribe(segment)
            saveTranscript(segment.index, text, provider)
        }
    }
    private fun transcript(index: Int): JSONObject? = File(directory, "%06d.json".format(index)).takeIf { it.exists() }
        ?.let { JSONObject(it.readText()) }

    private fun atomicWrite(destination: File, bytes: ByteArray) {
        val temporary = File(directory, destination.name + ".tmp")
        RandomAccessFile(temporary, "rw").use { it.setLength(0); it.write(bytes); it.fd.sync() }
        check(temporary.renameTo(destination)) { "Could not persist recording progress." }
    }

    private fun header(size: Int): ByteArray = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        .put("RIFF".toByteArray()).putInt(36 + size).put("WAVEfmt ".toByteArray())
        .putInt(16).putShort(1).putShort(1).putInt(16000).putInt(32000).putShort(2).putShort(16)
        .put("data".toByteArray()).putInt(size).array()
}
