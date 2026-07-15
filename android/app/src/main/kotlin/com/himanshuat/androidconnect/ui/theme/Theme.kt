package com.himanshuat.androidconnect.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val DarkColors = darkColorScheme(
    primary = AccentBright,
    onPrimary = Chalk,
    background = Ink,
    onBackground = Chalk,
    surface = Ink,
    surfaceVariant = InkElevated,
    onSurface = Chalk,
    onSurfaceVariant = ChalkMuted,
    outline = InkLine,
    error = Danger,
)

private val LightColors = lightColorScheme(
    primary = Accent,
    onPrimary = Chalk,
    background = Chalk,
    onBackground = Ink,
    surface = Chalk,
    onSurface = Ink,
    outline = InkLine,
    error = Danger,
)

@Composable
fun AndroidConnectTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = Typography,
        content = content,
    )
}
