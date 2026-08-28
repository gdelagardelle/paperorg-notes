package com.paperorg.notes.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val Primary = Color(0xFF142337)
val Accent = Color(0xFFF56A0A)
val Background = Color(0xFFF5F7FB)
val HeroGradientBottom = Color(0xFFF2F6FC)
val Surface = Color(0xFFFFFFFF)
val Border = Color(0xFFE0E5EC)
val AccentSoft = Color(0x24F56A0A)
val PrimarySoft = Color(0x1A142337)
val TextSecondary = Color(0xFF4D607B)
val Error = Color(0xFFD64545)

private val colors = lightColorScheme(
    primary = Primary,
    onPrimary = Color.White,
    secondary = Accent,
    onSecondary = Color.White,
    background = Background,
    onBackground = Primary,
    surface = Surface,
    onSurface = Primary,
    error = Error,
)

private val type = Typography(
    headlineLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Primary),
    headlineMedium = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Primary),
    titleLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Primary),
    titleMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Primary),
    bodyLarge = TextStyle(fontSize = 13.sp, color = Primary),
    bodyMedium = TextStyle(fontSize = 13.sp, color = Primary),
    bodySmall = TextStyle(fontSize = 11.sp, color = TextSecondary),
    labelLarge = TextStyle(fontSize = 13.sp, color = Primary),
    labelMedium = TextStyle(fontSize = 12.sp, color = TextSecondary),
    labelSmall = TextStyle(fontSize = 11.sp, color = TextSecondary),
)

@Composable
fun PaperorgNotesTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, typography = type, content = content)
}

