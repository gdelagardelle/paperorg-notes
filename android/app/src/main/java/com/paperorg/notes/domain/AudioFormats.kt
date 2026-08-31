package com.paperorg.notes.domain

/**
 * The containers the API accepts, and what to call them when uploading.
 *
 * Providers pick their decoder from the filename extension, so sending an MP3
 * announced as `audio/m4a` gets it rejected upstream even though the API itself
 * reads the container from the bytes.
 */
enum class AudioFormat(val extension: String, val mimeType: String) {
    M4A("m4a", "audio/m4a"),
    MP3("mp3", "audio/mpeg"),
    WAV("wav", "audio/wav"),
    ;

    companion object {
        /**
         * What the document picker should offer. Several of these are aliases for
         * the same container; devices and file providers disagree about which one
         * they report, and a type the picker does not list cannot be chosen at all.
         */
        val pickerMimeTypes = arrayOf(
            "audio/mpeg",
            "audio/mp3",
            "audio/wav",
            "audio/x-wav",
            "audio/vnd.wave",
            "audio/mp4",
            "audio/m4a",
            "audio/x-m4a",
            "audio/aac",
        )

        /** Recordings are always M4A, so an unknown name is treated as one. */
        fun forFileName(name: String): AudioFormat =
            entries.firstOrNull { name.endsWith(".${it.extension}", ignoreCase = true) } ?: M4A

        /**
         * The container an import actually is, or null if it is not one we accept.
         *
         * The reported MIME type is tried first and the filename second, because
         * some providers report `application/octet-stream` for everything while
         * others hand over a name with no extension.
         */
        fun forImport(mimeType: String?, fileName: String?): AudioFormat? {
            val normalised = mimeType?.substringBefore(';')?.trim()?.lowercase()
            when (normalised) {
                "audio/mpeg", "audio/mp3", "audio/x-mp3", "audio/mpeg3" -> return MP3
                "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave" -> return WAV
                "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/mp4a-latm" -> return M4A
            }
            return fileName?.let { name ->
                entries.firstOrNull { name.endsWith(".${it.extension}", ignoreCase = true) }
            }
        }
    }
}

/**
 * Whether an imported file can be sent at all, decided before it is copied.
 *
 * These are the same limits the API enforces. Checking them here is not a
 * substitute for the server -- it is what stops the app spending a user's time
 * copying and uploading a file that will be refused on arrival.
 */
object ImportPolicy {
    /** The API's own upload ceiling. */
    const val MAX_UPLOAD_BYTES = 100L * 1024 * 1024
    private const val MIN_SECONDS = 0.5

    /** A message to show, or null if the file is acceptable. */
    fun refusal(seconds: Double, bytes: Long, maxRecordingMinutes: Int?): String? {
        if (seconds < MIN_SECONDS) {
            return "This recording is too short to transcribe."
        }
        // Absent until the server has told us, and a client that invented a
        // default would refuse files the server would have accepted.
        if (maxRecordingMinutes != null && maxRecordingMinutes > 0 &&
            seconds > maxRecordingMinutes * 60.0
        ) {
            return "This audio is longer than $maxRecordingMinutes minutes. " +
                "Split it into shorter parts."
        }
        if (bytes > MAX_UPLOAD_BYTES) {
            val megabytes = MAX_UPLOAD_BYTES / (1024 * 1024)
            return "This file is larger than $megabytes MB. WAV is about 10 MB per " +
                "minute, so try an MP3 or M4A of the same recording."
        }
        return null
    }
}
