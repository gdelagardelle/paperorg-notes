package com.paperorg.notes.data

object UserFacingError {
    fun message(error: Exception): String {
        val api = error as? NotesApiException
        val detail = (api?.message ?: error.message).orEmpty()
        if (detail.contains("Sign in with Apple", ignoreCase = true)) {
            return "Paperorg could not send from the server yet. The notes-api Android email path needs a deploy."
        }
        if (detail.contains("could not be verified", ignoreCase = true)) {
            return "Google Play could not confirm this install. The recording was saved in Notes. A USB debug build can fail Play Integrity until the app is on an internal testing track."
        }
        if (detail.contains("integrity", ignoreCase = true)) {
            return "Play Integrity failed. Your recording was saved in Notes."
        }
        return detail.ifBlank { "Something went wrong." }
    }
}
