package com.paperorg.notes.data

interface PcmMicrophone {
    fun start()
    fun read(buffer: ByteArray): Int
    fun stop()
}

class ContinuousCapture(
    private val microphone: PcmMicrophone,
    private val audio: SegmentedAudio,
    private val maxSeconds: Double,
    private val hasSpace: () -> Boolean,
    private val onSegment: () -> Unit = {},
) {
    @Volatile var paused = false
    @Volatile var stopped = false
        private set
    private val microphoneStopped = java.util.concurrent.atomic.AtomicBoolean(false)
    private fun stopMicrophone() { if (microphoneStopped.compareAndSet(false, true)) microphone.stop() }
    fun requestStop() { stopped = true; stopMicrophone() }
    fun run() {
        val limit = (maxSeconds * 32000).toLong() / 2 * 2
        require(limit > 0)
        var written = 0L
        var sealed = audio.segments().size
        val buffer = ByteArray(3200)
        try {
            if (!stopped) microphone.start()
            while (!stopped && written < limit) {
                check(hasSpace()) { "Storage is almost full. Your recorded audio has been saved." }
                val count = microphone.read(buffer)
                if (stopped) break
                check(count > 0 && count % 2 == 0) { "Microphone interrupted. Your recorded audio has been saved." }
                if (paused) continue // Keep the same microphone session; omit paused samples.
                val accepted = minOf(count.toLong(), limit - written).toInt()
                audio.append(buffer, accepted)
                written += accepted
                val nowSealed = audio.segments().size
                if (nowSealed > sealed) { sealed = nowSealed; onSegment() }
            }
        } finally {
            try { stopMicrophone() } finally { audio.finish() }
        }
    }
}
