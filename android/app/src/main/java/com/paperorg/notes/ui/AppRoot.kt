package com.paperorg.notes.ui

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paperorg.notes.R
import com.paperorg.notes.data.RecordingState
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.AudioFormat
import com.paperorg.notes.domain.DurationFormat
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.domain.ProcessingStage
import com.paperorg.notes.domain.ProviderId
import com.paperorg.notes.domain.SummaryParser
import com.paperorg.notes.ui.theme.Accent
import com.paperorg.notes.ui.theme.AccentSoft
import com.paperorg.notes.ui.theme.Background
import com.paperorg.notes.ui.theme.Border
import com.paperorg.notes.ui.theme.HeroGradientBottom
import com.paperorg.notes.ui.theme.Primary
import com.paperorg.notes.ui.theme.PrimarySoft
import com.paperorg.notes.ui.theme.Surface
import com.paperorg.notes.ui.theme.TextSecondary

@Composable
fun AppRoot(model: AppViewModel) {
    val privacy by model.privacyAccepted.collectAsStateWithLifecycle()
    val context = LocalContext.current
    if (!privacy) {
        PrivacyScreen(onAccept = model::acceptPrivacy)
        return
    }
    val record by model.record.collectAsStateWithLifecycle()
    val notes by model.notes.collectAsStateWithLifecycle()
    val query by model.search.collectAsStateWithLifecycle()
    val playingId by model.playingNoteId.collectAsStateWithLifecycle()
    var tab by remember { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf<Note?>(null) }
    if (selected != null) {
        val live = notes.find { it.id == selected!!.id } ?: selected!!
        NoteDetailScreen(
            note = live,
            processing = record.processing,
            processingStage = record.processingStage,
            error = record.error,
            hasAudio = model.hasAudio(live),
            playing = playingId == live.id,
            onBack = {
                model.stopPlayback()
                selected = null
            },
            onFavorite = { model.toggleFavorite(live) },
            onRetry = { language -> model.retry(live, language) },
            onPlay = { model.togglePlayback(live) },
            onResummarize = { model.resummarize(live) },
            onSendEmail = { onResult -> model.sendNoteEmail(live, onResult) },
            onExportPdf = { onResult -> model.sharePdf(context, live, onResult) },
            onDismissError = model::dismissError,
        )
        return
    }
    Scaffold(
        containerColor = Background,
        bottomBar = {
            NavigationBar(
                containerColor = Surface,
                tonalElevation = 0.dp,
            ) {
                val items = listOf(
                    stringResource(R.string.tab_record),
                    stringResource(R.string.tab_notes),
                    stringResource(R.string.tab_search),
                    stringResource(R.string.tab_settings),
                )
                val icons = listOf(Icons.Filled.Mic, Icons.Filled.Description, Icons.Filled.Search, Icons.Filled.Settings)
                items.forEachIndexed { index, label ->
                    NavigationBarItem(
                        selected = tab == index,
                        onClick = { tab = index },
                        icon = { Icon(icons[index], contentDescription = label) },
                        label = { Text(label) },
                        colors = NavigationBarItemDefaults.colors(indicatorColor = Accent.copy(alpha = 0.16f), selectedIconColor = Accent),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (tab) {
                0 -> RecordScreen(model, record, notes, onOpen = { selected = it })
                1 -> NotesScreen(notes, onOpen = { selected = it }, onDelete = model::delete)
                2 -> SearchScreen(notes, query, model::setSearch, onOpen = { selected = it })
                else -> SettingsScreen(model, notes, record.usage)
            }
        }
    }
}

@Composable
private fun PrivacyScreen(onAccept: () -> Unit) {
    var agreed by remember { mutableStateOf(false) }
    val uri = LocalUriHandler.current
    Column(
        Modifier.fillMaxSize().background(Background).padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(stringResource(R.string.privacy_title), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Primary)
        Text(stringResource(R.string.privacy_intro), color = TextSecondary)
        PrivacyRow(stringResource(R.string.privacy_row_local_title), stringResource(R.string.privacy_row_local_detail))
        PrivacyRow(stringResource(R.string.privacy_row_control_title), stringResource(R.string.privacy_row_control_detail))
        PrivacyRow(stringResource(R.string.privacy_row_gdpr_title), stringResource(R.string.privacy_row_gdpr_detail))
        PrivacyRow(stringResource(R.string.privacy_row_providers_title), stringResource(R.string.privacy_row_providers_detail))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(checked = agreed, onCheckedChange = { agreed = it })
            Text(stringResource(R.string.privacy_agree), modifier = Modifier.padding(start = 8.dp))
        }
        TextButton(onClick = { uri.openUri("https://gdelagardelle.github.io/paperorg-notes/privacy.html") }) {
            Text(stringResource(R.string.privacy_view_policy))
        }
        Button(
            onClick = onAccept,
            enabled = agreed,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Primary),
        ) { Text(stringResource(R.string.privacy_continue)) }
    }
}

@Composable
private fun PrivacyRow(title: String, detail: String) {
    Card(colors = CardDefaults.cardColors(containerColor = Surface), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold, color = Primary)
            Text(detail, color = TextSecondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun RecordScreen(
    model: AppViewModel,
    state: RecordUiState,
    notes: List<Note>,
    onOpen: (Note) -> Unit,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val recording = state.recordingState != RecordingState.Idle
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants[Manifest.permission.RECORD_AUDIO] == true) model.startRecording()
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(model::importAudio)
    }
    DisposableEffect(recording) {
        val window = (view.context as? Activity)?.window
        if (recording) window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    fun startOrStop() {
        if (recording) {
            model.stopAndProcess()
        } else {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            if (granted) {
                model.startRecording()
            } else {
                val needed = mutableListOf(Manifest.permission.RECORD_AUDIO)
                if (Build.VERSION.SDK_INT >= 33) needed += Manifest.permission.POST_NOTIFICATIONS
                permission.launch(needed.toTypedArray())
            }
        }
    }
    val status = state.recordingState.statusLabel()
    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Background, HeroGradientBottom)))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Image(
                painter = painterResource(R.drawable.launch_logo),
                contentDescription = null,
                modifier = Modifier.size(44.dp),
            )
            Spacer(Modifier.width(14.dp))
            Column {
                Text(stringResource(R.string.app_name), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Primary)
                Text(stringResource(R.string.brand_tagline), color = TextSecondary, fontSize = 14.sp)
            }
        }
        SurfaceCard {
            Column(Modifier.alpha(if (recording) 0.72f else 1f)) {
                ChipSection(stringResource(R.string.record_language), enabled = !recording) {
                    AppLanguage.recordPicker.forEach { language ->
                        SelectionChip(
                            title = "${language.flag} ${language.displayName}",
                            selected = state.language == language,
                            enabled = !recording,
                            onClick = { model.setLanguage(language) },
                        )
                    }
                }
                Text(
                    stringResource(R.string.record_language_hint),
                    color = TextSecondary,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(top = 8.dp),
                )
                Spacer(Modifier.height(18.dp))
                ChipSection(stringResource(R.string.record_note_style), enabled = !recording) {
                    OutputType.entries.forEach { type ->
                        SelectionChip(
                            title = type.label(),
                            selected = state.outputType == type,
                            enabled = !recording,
                            onClick = { model.setOutput(type) },
                        )
                    }
                }
            }
        }
        state.usage?.let { usage ->
            SurfaceCard {
                Text(stringResource(if (usage.isPro) R.string.record_plan_pro else R.string.record_plan_free), fontWeight = FontWeight.SemiBold, color = Primary)
                Text(
                    stringResource(R.string.usage_minutes_left, usage.minutesRemaining, usage.minutesLimit),
                    color = TextSecondary,
                    fontSize = 13.sp,
                )
                usage.maxRecordingMinutes?.let { cap ->
                    Text(
                        stringResource(R.string.usage_cap, cap),
                        color = TextSecondary,
                        fontSize = 12.sp,
                    )
                }
            }
        }
        SurfaceCard(padding = 28.dp) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                RecordHeroButton(state = state.recordingState, onClick = { startOrStop() })
                Text(
                    state.durationLabel,
                    fontSize = 36.sp,
                    fontWeight = FontWeight.Light,
                    color = Primary,
                )
                Text(status, color = TextSecondary, fontWeight = FontWeight.Medium)
                if (recording) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        RecordControlCapsule(
                            title = if (state.recordingState == RecordingState.Paused) stringResource(R.string.record_resume) else stringResource(R.string.record_pause),
                            icon = if (state.recordingState == RecordingState.Paused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                            destructive = false,
                            onClick = model::pauseOrResume,
                        )
                        RecordControlCapsule(
                            title = stringResource(R.string.record_stop),
                            icon = Icons.Filled.Stop,
                            destructive = true,
                            onClick = model::stopAndProcess,
                        )
                    }
                }
                if (state.processing) {
                    CircularProgressIndicator(color = Accent, modifier = Modifier.size(28.dp))
                    Text(state.processingStage?.label() ?: stringResource(R.string.record_processing), color = TextSecondary)
                }
                if (!recording) {
                    TextButton(
                        onClick = { importer.launch(AudioFormat.pickerMimeTypes) },
                        enabled = !state.processing,
                    ) { Text(stringResource(R.string.record_import)) }
                    Text(importHint(state.usage?.maxRecordingMinutes), color = TextSecondary, fontSize = 12.sp)
                }
            }
        }
        state.error?.let { error ->
            SurfaceCard {
                Text(error, color = com.paperorg.notes.ui.theme.Error, fontSize = 14.sp)
                TextButton(onClick = model::dismissError) { Text(stringResource(R.string.common_dismiss)) }
            }
        }
        Text(stringResource(R.string.record_recent), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Primary, modifier = Modifier.padding(top = 8.dp))
        Text(stringResource(R.string.record_recent_subtitle), color = TextSecondary, fontSize = 14.sp)
        if (notes.isEmpty()) {
            SurfaceCard(padding = 28.dp) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.Mic, contentDescription = null, tint = Accent.copy(alpha = 0.7f), modifier = Modifier.size(36.dp))
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.record_empty_title), fontWeight = FontWeight.SemiBold, color = Primary)
                    Text(stringResource(R.string.record_empty_subtitle), color = TextSecondary, fontSize = 14.sp)
                }
            }
        } else {
            notes.take(5).forEach { note ->
                NoteCard(note, compact = true, onOpen = { onOpen(note) })
            }
        }
    }
}

@Composable
private fun importHint(maxMinutes: Int?): String {
    return if (maxMinutes != null && maxMinutes > 0) {
        stringResource(R.string.record_import_hint_limit, maxMinutes)
    } else {
        stringResource(R.string.record_import_hint)
    }
}

@Composable
private fun SurfaceCard(padding: androidx.compose.ui.unit.Dp = 16.dp, content: @Composable () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Surface),
        modifier = Modifier.fillMaxWidth().shadow(6.dp, RoundedCornerShape(20.dp), ambientColor = Primary.copy(alpha = 0.06f), spotColor = Primary.copy(alpha = 0.06f)),
        border = BorderStroke(1.dp, Border),
        shape = RoundedCornerShape(20.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(padding)) { content() }
    }
}

@Composable
private fun ChipSection(label: String, enabled: Boolean, chips: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label.uppercase(), color = TextSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .fillMaxWidth()
                .then(if (enabled) Modifier else Modifier),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) { chips() }
    }
}

@Composable
internal fun SelectionChip(title: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val bg = if (selected) Primary else Surface
    val fg = if (selected) Color.White else Primary
    val stroke = if (selected) Primary else Border
    Text(
        title,
        color = fg,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(bg)
            .border(1.dp, stroke, RoundedCornerShape(50))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
    )
}

@Composable
private fun RecordHeroButton(state: RecordingState, onClick: () -> Unit) {
    val transition = rememberInfiniteTransition(label = "pulse")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = 1.06f,
        animationSpec = infiniteRepeatable(tween(1000), RepeatMode.Reverse),
        label = "pulse",
    )
    val scale = if (state == RecordingState.Recording) pulse else 1f
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(156.dp).clickable(onClick = onClick)) {
        Box(
            Modifier
                .size(156.dp)
                .scale(scale)
                .border(10.dp, Accent.copy(alpha = 0.18f), CircleShape),
        )
        Box(Modifier.size(132.dp).clip(CircleShape).background(AccentSoft))
        Box(
            Modifier
                .size(96.dp)
                .shadow(16.dp, CircleShape, ambientColor = Accent.copy(alpha = 0.35f), spotColor = Accent.copy(alpha = 0.35f))
                .clip(CircleShape)
                .background(Accent),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (state == RecordingState.Idle) Icons.Filled.Mic else Icons.Filled.Stop,
                contentDescription = if (state == RecordingState.Idle) stringResource(R.string.record_start) else stringResource(R.string.record_stop),
                tint = Color.White,
                modifier = Modifier.size(34.dp),
            )
        }
    }
}

@Composable
private fun RecordControlCapsule(
    title: String,
    icon: ImageVector,
    destructive: Boolean,
    onClick: () -> Unit,
) {
    val fg = if (destructive) com.paperorg.notes.ui.theme.Error else Primary
    val bg = if (destructive) com.paperorg.notes.ui.theme.Error.copy(alpha = 0.10f) else PrimarySoft
    val stroke = if (destructive) com.paperorg.notes.ui.theme.Error.copy(alpha = 0.25f) else Border
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(bg)
            .border(1.dp, stroke, RoundedCornerShape(50))
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(16.dp))
        Text(title, color = fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
    }
}

@Composable
private fun SearchScreen(notes: List<Note>, query: String, onQuery: (String) -> Unit, onOpen: (Note) -> Unit) {
    val results = notes.filter { it.matches(query) }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Text(stringResource(R.string.search_title), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Primary)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(value = query, onValueChange = onQuery, modifier = Modifier.fillMaxWidth(), placeholder = { Text(stringResource(R.string.search_placeholder)) })
        Spacer(Modifier.height(12.dp))
        if (query.isBlank()) {
            Text(stringResource(R.string.search_empty), color = TextSecondary)
        } else if (results.isEmpty()) {
            Text(stringResource(R.string.search_no_match), color = TextSecondary)
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(results, key = { it.id }) { note ->
                    NoteCard(note, onOpen = { onOpen(note) })
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NoteDetailScreen(
    note: Note,
    processing: Boolean,
    processingStage: ProcessingStage?,
    error: String?,
    hasAudio: Boolean,
    playing: Boolean,
    onBack: () -> Unit,
    onFavorite: () -> Unit,
    onRetry: (AppLanguage) -> Unit,
    onPlay: () -> Unit,
    onResummarize: () -> Unit,
    onSendEmail: (onResult: (String) -> Unit) -> Unit,
    onExportPdf: (onResult: (String) -> Unit) -> Unit,
    onDismissError: () -> Unit,
) {
    var retryLanguage by remember(note.id) { mutableStateOf(AppLanguage.fromCode(note.language)) }
    var detailTab by remember(note.id) { mutableIntStateOf(0) }
    var emailResult by remember(note.id) { mutableStateOf<String?>(null) }
    LaunchedEffect(note.language) {
        retryLanguage = AppLanguage.fromCode(note.language)
    }
    val structured = remember(note.structuredJson) {
        note.structuredJson?.let { runCatching { SummaryParser.parse(it) }.getOrNull() }
    }
    val language = AppLanguage.fromCode(note.language)
    val provider = ProviderId.label(note.primaryProvider)
    val transcript = note.displayTranscript
    Scaffold(
        containerColor = Background,
        topBar = {
            TopAppBar(
                title = { Text(note.title) },
                navigationIcon = { TextButton(onClick = onBack) { Text(stringResource(R.string.common_back)) } },
                actions = {
                    IconButton(onClick = onFavorite) {
                        Icon(if (note.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder, contentDescription = stringResource(R.string.notes_favorite), tint = Accent)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Background, titleContentColor = Primary),
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).padding(20.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            listOfNotNull(
                DurationFormat.format(note.durationSeconds),
                "${language.flag} ${language.displayName}",
                provider?.let { "via $it" },
                stringResource(noteStatusString(note.status)),
            ).joinToString(" · "),
                color = TextSecondary,
            )
            if (processing) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(color = Accent, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text(processingStage?.label() ?: stringResource(R.string.record_processing), color = TextSecondary)
                }
            }
            error?.let {
                Text(it, color = com.paperorg.notes.ui.theme.Error, fontSize = 14.sp)
                TextButton(onClick = onDismissError) { Text(stringResource(R.string.common_dismiss)) }
            }
            if (note.status == "failed") {
                Text(note.errorMessage ?: stringResource(R.string.note_processing_failed), color = com.paperorg.notes.ui.theme.Error)
            }
            if (hasAudio) {
                ChipSection(stringResource(R.string.note_retry_language), enabled = !processing) {
                    AppLanguage.recordPicker.forEach { option ->
                        SelectionChip(
                            title = "${option.flag} ${option.displayName}",
                            selected = retryLanguage == option,
                            enabled = !processing,
                            onClick = { retryLanguage = option },
                        )
                    }
                }
                Text(
                    stringResource(R.string.note_retry_hint),
                    color = TextSecondary,
                    fontSize = 12.sp,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { onRetry(retryLanguage) },
                        enabled = !processing,
                        colors = ButtonDefaults.buttonColors(containerColor = Primary),
                    ) { Text(stringResource(R.string.note_transcribe_again)) }
                    TextButton(onClick = onPlay, enabled = !processing) {
                        Text(if (playing) stringResource(R.string.note_stop_audio) else stringResource(R.string.note_play_audio))
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(
                    onClick = onResummarize,
                    enabled = !processing && transcript.isNotBlank(),
                ) { Text(stringResource(R.string.note_resummarize)) }
                TextButton(
                    onClick = {
                        emailResult = null
                        onSendEmail { result -> emailResult = result }
                    },
                    enabled = !processing,
                ) { Text(stringResource(R.string.note_send_email)) }
                TextButton(
                    onClick = {
                        emailResult = null
                        onExportPdf { result -> emailResult = result }
                    },
                    enabled = !processing && transcript.isNotBlank(),
                ) { Text(stringResource(R.string.note_export_pdf)) }
            }
            emailResult?.let {
                Text(it, color = TextSecondary, fontSize = 13.sp)
            }
            TabRow(selectedTabIndex = detailTab, containerColor = Surface, contentColor = Primary) {
                Tab(selected = detailTab == 0, onClick = { detailTab = 0 }, text = { Text(stringResource(R.string.note_tab_transcript)) })
                Tab(selected = detailTab == 1, onClick = { detailTab = 1 }, text = { Text(stringResource(R.string.note_tab_summary)) })
                Tab(selected = detailTab == 2, onClick = { detailTab = 2 }, text = { Text(stringResource(R.string.note_tab_actions)) })
            }
            when (detailTab) {
                0 -> {
                    if (transcript.isBlank()) {
                        Text(stringResource(R.string.note_no_transcript), color = TextSecondary)
                        if (hasAudio) {
                            Text(
                                stringResource(R.string.note_no_transcript_hint),
                                color = TextSecondary,
                                fontSize = 12.sp,
                            )
                        }
                    } else {
                        Text(transcript, color = Primary)
                    }
                }
                1 -> {
                    val summary = note.displaySummaryShort
                    if (summary.isBlank()) {
                        Text(stringResource(R.string.note_no_summary), color = TextSecondary)
                    } else {
                        Text(stringResource(R.string.note_summary_heading), fontWeight = FontWeight.SemiBold)
                        Text(summary)
                    }
                    note.summaryDetailed?.takeIf { it.isNotBlank() && it != note.summaryShort }?.let {
                        Text(stringResource(R.string.note_detail_heading), fontWeight = FontWeight.SemiBold)
                        Text(it)
                    }
                    structured?.let { output ->
                        NoteListSection(stringResource(R.string.note_key_ideas), output.keyIdeas)
                        NoteListSection(stringResource(R.string.note_decisions), output.decisions)
                        NoteListSection(stringResource(R.string.note_open_questions), output.openQuestions)
                    }
                }
                else -> {
                    structured?.let { output ->
                        NoteListSection(stringResource(R.string.note_actions), output.actionItems)
                    } ?: Text(stringResource(R.string.note_no_actions), color = TextSecondary)
                }
            }
        }
    }
}

@Composable
private fun NoteListSection(title: String, items: List<String>) {
    if (items.isEmpty()) return
    Text(title, fontWeight = FontWeight.SemiBold)
    items.forEach { item ->
        Text("• $item")
    }
}

