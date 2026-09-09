package com.paperorg.notes.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private object Brand {
    val Navy = Color(0xFF142337)
    val Orange = Color(0xFFF56A0A)
    val Mist = Color(0xFFF5F7FB)
    val White = Color.White
    val BorderLight = Color(0xFFE0E5EC)
    val SecondaryLight = Color(0xFF4D607B)
    val ErrorLight = Color(0xFFD64545)
    val HeroBottom = Color(0xFFF2F6FC)
    val DarkBg = Color(0xFF0B1220)
    val DarkSurface = Color(0xFF162033)
    val DarkInk = Color(0xFFF5F7FB)
    val DarkSecondary = Color(0xFF9AA8BC)
    val DarkBorder = Color(0xFF2C3A51)
    val ErrorDark = Color(0xFFFF8A80)
}

data class NotesPalette(
    val ink: Color,
    val accent: Color,
    val background: Color,
    val surface: Color,
    val border: Color,
    val textSecondary: Color,
    val error: Color,
    val primarySoft: Color,
    val accentSoft: Color,
    val filled: Color,
    val onFilled: Color,
    val heroBottom: Color,
)

private val LightPalette = NotesPalette(
    ink = Brand.Navy,
    accent = Brand.Orange,
    background = Brand.Mist,
    surface = Brand.White,
    border = Brand.BorderLight,
    textSecondary = Brand.SecondaryLight,
    error = Brand.ErrorLight,
    primarySoft = Brand.Navy.copy(alpha = 0.10f),
    accentSoft = Brand.Orange.copy(alpha = 0.14f),
    filled = Brand.Navy,
    onFilled = Brand.White,
    heroBottom = Brand.HeroBottom,
)

private val DarkPalette = NotesPalette(
    ink = Brand.DarkInk,
    accent = Brand.Orange,
    background = Brand.DarkBg,
    surface = Brand.DarkSurface,
    border = Brand.DarkBorder,
    textSecondary = Brand.DarkSecondary,
    error = Brand.ErrorDark,
    primarySoft = Brand.White.copy(alpha = 0.12f),
    accentSoft = Brand.Orange.copy(alpha = 0.22f),
    filled = Brand.Orange,
    onFilled = Brand.White,
    heroBottom = Brand.DarkBg,
)

private val LocalNotesPalette = staticCompositionLocalOf { LightPalette }

val Primary: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.ink
val Accent: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.accent
val Background: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.background
val HeroGradientBottom: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.heroBottom
val Surface: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.surface
val Border: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.border
val AccentSoft: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.accentSoft
val PrimarySoft: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.primarySoft
val TextSecondary: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.textSecondary
val Error: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.error
val FilledButton: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.filled
val OnFilledButton: Color
    @Composable @ReadOnlyComposable get() = LocalNotesPalette.current.onFilled

private val LightScheme = lightColorScheme(
    primary = Brand.Navy,
    onPrimary = Brand.White,
    secondary = Brand.Orange,
    onSecondary = Brand.White,
    background = Brand.Mist,
    onBackground = Brand.Navy,
    surface = Brand.White,
    onSurface = Brand.Navy,
    onSurfaceVariant = Brand.SecondaryLight,
    outline = Brand.BorderLight,
    error = Brand.ErrorLight,
    onError = Brand.White,
)

private val DarkScheme = darkColorScheme(
    primary = Brand.Orange,
    onPrimary = Brand.White,
    secondary = Brand.Orange,
    onSecondary = Brand.White,
    background = Brand.DarkBg,
    onBackground = Brand.DarkInk,
    surface = Brand.DarkSurface,
    onSurface = Brand.DarkInk,
    onSurfaceVariant = Brand.DarkSecondary,
    outline = Brand.DarkBorder,
    error = Brand.ErrorDark,
    onError = Brand.DarkBg,
)

private val type = Typography(
    headlineLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold),
    headlineMedium = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 13.sp),
    bodyMedium = TextStyle(fontSize = 13.sp),
    bodySmall = TextStyle(fontSize = 11.sp),
    labelLarge = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 12.sp),
    labelSmall = TextStyle(fontSize = 11.sp),
)

@Composable
fun filledButtonColors() = ButtonDefaults.buttonColors(
    containerColor = FilledButton,
    contentColor = OnFilledButton,
    disabledContainerColor = FilledButton.copy(alpha = 0.38f),
    disabledContentColor = OnFilledButton.copy(alpha = 0.70f),
)

@Composable
fun textButtonColors() = ButtonDefaults.textButtonColors(
    contentColor = Primary,
    disabledContentColor = Primary.copy(alpha = 0.38f),
)

@Composable
fun destructiveTextButtonColors() = ButtonDefaults.textButtonColors(
    contentColor = Error,
    disabledContentColor = Error.copy(alpha = 0.38f),
)

@Composable
fun notesSwitchColors() = SwitchDefaults.colors(
    checkedTrackColor = Accent,
    checkedThumbColor = Color.White,
    checkedBorderColor = Accent,
    uncheckedTrackColor = Border,
    uncheckedThumbColor = Surface,
    uncheckedBorderColor = Border,
)

@Composable
fun PaperorgNotesTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val palette = if (darkTheme) DarkPalette else LightPalette
    CompositionLocalProvider(LocalNotesPalette provides palette) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkScheme else LightScheme,
            typography = type,
            content = content,
        )
    }
}
