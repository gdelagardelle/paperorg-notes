package com.paperorg.notes

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.paperorg.notes.ui.theme.LightPalette
import com.paperorg.notes.ui.theme.DarkPalette
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeContrastTest {
    @Test fun bodyTextAndButtonsRemainReadableInBothThemes() {
        for (palette in listOf(LightPalette, DarkPalette)) {
            fun check(label: String, foreground: Color, background: Color) {
                val a = foreground.luminance()
                val b = background.luminance()
                val ratio = (maxOf(a, b) + 0.05f) / (minOf(a, b) + 0.05f)
                assertTrue("$label contrast $ratio must be at least 4.5:1", ratio >= 4.5f)
            }
            check("Filled button", palette.onFilled, palette.filled)
            for (background in listOf(palette.surface, palette.background)) {
                check("Error", palette.error, background)
                check("Accent text", palette.accentText, background)
                check("Secondary text", palette.textSecondary, background)
            }
        }
    }
}
