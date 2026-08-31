package com.paperorg.notes.domain

import org.json.JSONArray
import org.json.JSONObject

object JsonSupport {
    fun obj(raw: String): JSONObject = JSONObject(raw)

    fun string(obj: JSONObject, vararg keys: String): String? {
        for (key in keys) {
            if (obj.has(key) && !obj.isNull(key)) {
                val value = obj.optString(key).trim()
                if (value.isNotEmpty()) return value
            }
        }
        return null
    }

    fun stringList(obj: JSONObject, vararg keys: String): List<String> {
        for (key in keys) {
            val array = obj.optJSONArray(key)
            if (array != null) {
                return (0 until array.length()).mapNotNull { index ->
                    array.optString(index).trim().takeIf { it.isNotEmpty() }
                }
            }
            if (obj.has(key) && !obj.isNull(key)) {
                val value = obj.optString(key).trim()
                if (value.isNotEmpty()) {
                    return value.split('\n').map { it.trim() }.filter { it.isNotEmpty() }
                }
            }
        }
        return emptyList()
    }
}

object UsageParser {
    fun parse(raw: String): UsageInfo {
        val obj = JSONObject(raw)
        // Read in both branches: the Platform's envelope carries this too, and
        // reading it in only one is how the attestation flag got lost before.
        val maxRecordingMinutes = if (obj.has("max_recording_minutes")) {
            obj.optInt("max_recording_minutes").takeIf { it > 0 }
        } else {
            null
        }
        val metrics = obj.optJSONObject("metrics")
        if (metrics != null) {
            val minutes = metrics.optJSONObject("transcription.minutes")
            return UsageInfo(
                isPro = obj.optBoolean("is_pro"),
                minutesLimit = minutes?.optDouble("limit", 0.0)?.toInt() ?: 0,
                minutesUsed = minutes?.optDouble("used", 0.0) ?: 0.0,
                minutesRemaining = minutes?.optDouble("remaining", 0.0) ?: 0.0,
                periodKey = obj.optString("period_key"),
                proExpiresAt = obj.optString("pro_expires_at").takeIf { it.isNotEmpty() && it != "null" },
                appAttestRequired = obj.optBoolean("app_attest_required"),
                playIntegrityRequired = obj.optBoolean("play_integrity_required"),
                maxRecordingMinutes = maxRecordingMinutes,
            )
        }
        return UsageInfo(
            isPro = obj.optBoolean("is_pro"),
            minutesLimit = obj.optInt("minutes_limit"),
            minutesUsed = obj.optDouble("minutes_used"),
            minutesRemaining = obj.optDouble("minutes_remaining"),
            periodKey = obj.optString("period_key"),
            proExpiresAt = obj.optString("pro_expires_at").takeIf { it.isNotEmpty() && it != "null" },
            appAttestRequired = obj.optBoolean("app_attest_required"),
            playIntegrityRequired = obj.optBoolean("play_integrity_required"),
            maxRecordingMinutes = maxRecordingMinutes,
        )
    }
}

object TranscriptParser {
    fun openaiText(raw: String): String = readableText(raw).orEmpty()

    fun luxAsrText(raw: String): String = readableText(raw).orEmpty()

    fun readableText(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        val extracted = extract(trimmed).trim()
        if (extracted.isEmpty()) return null
        return extracted
    }

    fun isRawJSON(text: String?): Boolean {
        val trimmed = text?.trim().orEmpty()
        if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return false
        return runCatching {
            if (trimmed.startsWith("[")) JSONArray(trimmed) else JSONObject(trimmed)
        }.isSuccess
    }

    private fun extract(trimmed: String): String =
        runCatching { extractUnchecked(trimmed) }.getOrDefault("")

    private fun extractUnchecked(trimmed: String): String {
        if (trimmed.startsWith("[")) return joinArray(JSONArray(trimmed))
        if (!trimmed.startsWith("{")) return trimmed
        val obj = JSONObject(trimmed)
        val fromText = textField(obj).trim()
        val fromSegments = obj.optJSONArray("segments")?.let { joinArray(it) }.orEmpty()
        return fromText.ifBlank { fromSegments }
    }

    private fun textField(obj: JSONObject): String {
        val value = when {
            obj.has("text") && !obj.isNull("text") -> obj.opt("text")
            obj.has("transcript") && !obj.isNull("transcript") -> obj.opt("transcript")
            else -> null
        } ?: return ""
        return when (value) {
            is JSONArray -> joinArray(value)
            is JSONObject -> extract(value.toString())
            else -> unwrapNested(value.toString().trim(), obj.toString())
        }
    }

    private fun unwrapNested(nested: String, parent: String): String = when {
        nested.startsWith("[") -> runCatching { joinArray(JSONArray(nested)) }.getOrDefault("")
        nested.startsWith("{") && nested != parent -> extract(nested)
        isRawJSON(nested) -> ""
        else -> nested
    }

    private fun joinArray(array: JSONArray): String =
        (0 until array.length()).mapNotNull { index ->
            val item = array.opt(index)
            when (item) {
                is JSONObject -> item.optString("text").trim().ifEmpty {
                    item.optString("transcript").trim()
                }.takeIf { it.isNotEmpty() }
                else -> item?.toString()?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
            }
        }.joinToString(" ").trim()
}

object SummaryParser {
    fun parse(raw: String): StructuredNote {
        val obj = unwrap(raw)
        return StructuredNote(
            title = JsonSupport.string(obj, "title"),
            shortSummary = JsonSupport.string(obj, "shortSummary", "short_summary", "summary").orEmpty(),
            detailedSummary = JsonSupport.string(
                obj,
                "detailedSummary",
                "detailed_summary",
                "long_summary",
            ) ?: JsonSupport.string(obj, "shortSummary", "short_summary", "summary").orEmpty(),
            keyIdeas = JsonSupport.stringList(obj, "keyIdeas", "key_ideas"),
            decisions = JsonSupport.stringList(obj, "decisions"),
            actionItems = actionItems(obj),
            openQuestions = JsonSupport.stringList(obj, "openQuestions", "open_questions"),
        )
    }

    private fun unwrap(raw: String): JSONObject {
        val trimmed = raw.trim().removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
        val obj = JSONObject(trimmed)
        if (obj.has("choices")) {
            val content = obj.getJSONArray("choices")
                .optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content")
            if (!content.isNullOrBlank()) return JSONObject(content)
        }
        return obj
    }

    private fun actionItems(obj: JSONObject): List<String> {
        val array = obj.optJSONArray("actionItems") ?: obj.optJSONArray("action_items")
        if (array != null) {
            return (0 until array.length()).mapNotNull { index ->
                val nested = array.optJSONObject(index)
                if (nested != null) JsonSupport.string(nested, "text", "title")
                else array.optString(index).trim().takeIf { it.isNotEmpty() }
            }
        }
        return JsonSupport.stringList(obj, "actionItems", "action_items")
    }
}

data class StructuredNote(
    val title: String?,
    val shortSummary: String,
    val detailedSummary: String,
    val keyIdeas: List<String>,
    val decisions: List<String>,
    val actionItems: List<String>,
    val openQuestions: List<String>,
)
