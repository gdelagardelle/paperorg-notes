package com.paperorg.notes

import com.paperorg.notes.domain.*
import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingLimitTest {
    private fun usage(pro: Boolean = false, remaining: Double = 60.0, cap: Int? = null) =
        UsageInfo(pro, 600, 0.0, remaining, "2026-09", null, false, false, cap)
    @Test fun unknownUsageCannotBypassFreeThreeMinuteCap() = assertEquals(180.0, RecordingLimit.seconds(null), 0.0)
    @Test fun unknownServerCapUsesPlanAndRemainingBudget() {
        assertEquals(180.0, RecordingLimit.seconds(usage()), 0.0)
        assertEquals(10800.0, RecordingLimit.seconds(usage(true, 300.0)), 0.0)
        assertEquals(90.0, RecordingLimit.seconds(usage(true, 1.5, 180)), 0.0)
        assertEquals(0.0, RecordingLimit.seconds(usage(remaining = 0.0)), 0.0)
    }
}
