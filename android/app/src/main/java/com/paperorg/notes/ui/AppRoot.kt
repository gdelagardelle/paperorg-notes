package com.paperorg.notes.ui

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paperorg.notes.R
import com.paperorg.notes.data.RecordingState
import com.paperorg.notes.domain.AppLanguage
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
                val items = listOf("Record", "Notes", "Search", "Settings")
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
        Text("Your recordings stay yours", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Primary)
        Text("Paperorg Notes records on this device, then sends audio to Paperorg for transcription and structuring. You can export or delete everything at any time.", color = TextSecondary)
        PrivacyRow("On-device capture", "Audio is recorded locally first.")
        PrivacyRow("You stay in control", "Export or delete all notes from Settings.")
        PrivacyRow("GDPR", "You can download a copy of your data or wipe this device.")
        PrivacyRow("Providers", "Luxembourgish goes to LuxASR first; other languages use OpenAI, then ElevenLabs.")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(checked = agreed, onCheckedChange = { agreed = it })
            Text("I understand and agree", modifier = Modifier.padding(start = 8.dp))
        }
        TextButton(onClick = { uri.openUri("https://gdelagardelle.github.io/paperorg-notes/privacy.html") }) {
            Text("View privacy policy")
        }
        Button(
            onClick = onAccept,
            enabled = agreed,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Primary),
        ) { Text("Continue") }
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
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.startRecording()
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
            if (granted) model.startRecording() else permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    val status = when (state.recordingState) {
        RecordingState.Idle -> "Tap to record"
        RecordingState.Recording -> "Recording"
        RecordingState.Paused -> "Paused"
    }
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
                Text("Paperorg Notes", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Primary)
                Text("Capture, transcribe, send", color = TextSecondary, fontSize = 14.sp)
            }
        }
        SurfaceCard {
            Column(Modifier.alpha(if (recording) 0.72f else 1f)) {
                ChipSection("Language", enabled = !recording) {
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
                    "Pick the language you spoke. Lëtzebuergesch uses LuxASR; other languages use OpenAI.",
                    color = TextSecondary,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(top = 8.dp),
                )
                Spacer(Modifier.height(18.dp))
                ChipSection("Note style", enabled = !recording) {
                    OutputType.entries.forEach { type ->
                        SelectionChip(
                            title = type.displayName,
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
                Text(if (usage.isPro) "Paperorg Pro" else "Included minutes", fontWeight = FontWeight.SemiBold, color = Primary)
                Text(
                    "${"%.1f".format(usage.minutesRemaining)} of ${usage.minutesLimit} minutes left this month",
                    color = TextSecondary,
                    fontSize = 13.sp,
                )
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
                            title = if (state.recordingState == RecordingState.Paused) "Resume" else "Pause",
                            icon = if (state.recordingState == RecordingState.Paused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                            destructive = false,
                            onClick = model::pauseOrResume,
                        )
                        RecordControlCapsule(
                            title = "Stop",
                            icon = Icons.Filled.Stop,
                            destructive = true,
                            onClick = model::stopAndProcess,
                        )
                    }
                }
                if (state.processing) {
                    CircularProgressIndicator(color = Accent, modifier = Modifier.size(28.dp))
                    Text(state.processingStage?.displayName ?: "Processing", color = TextSecondary)
                }
            }
        }
        state.error?.let { error ->
            SurfaceCard {
                Text(error, color = com.paperorg.notes.ui.theme.Error, fontSize = 14.sp)
                TextButton(onClick = model::dismissError) { Text("Dismiss") }
            }
        }
        Text("Recent notes", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Primary, modifier = Modifier.padding(top = 8.dp))
        Text("Your last captures", color = TextSecondary, fontSize = 14.sp)
        if (notes.isEmpty()) {
            SurfaceCard(padding = 28.dp) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Filled.Mic, contentDescription = null, tint = Accent.copy(alpha = 0.7f), modifier = Modifier.size(36.dp))
                    Spacer(Modifier.height(8.dp))
                    Text("No notes yet", fontWeight = FontWeight.SemiBold, color = Primary)
                    Text("Tap the orange button to record.", color = TextSecondary, fontSize = 14.sp)
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
                contentDescription = if (state == RecordingState.Idle) "Start recording" else "Stop",
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
        Text("Search", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Primary)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(value = query, onValueChange = onQuery, modifier = Modifier.fillMaxWidth(), placeholder = { Text("Search transcripts and summaries") })
        Spacer(Modifier.height(12.dp))
        if (query.isBlank()) {
            Text("Type to search titles, transcripts, and summaries.", color = TextSecondary)
        } else if (results.isEmpty()) {
            Text("No matching notes.", color = TextSecondary)
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
                navigationIcon = { TextButton(onClick = onBack) { Text("Back") } },
                actions = {
                    IconButton(onClick = onFavorite) {
                        Icon(if (note.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder, contentDescription = "Favorite", tint = Accent)
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
                    note.status,
                ).joinToString(" · "),
                color = TextSecondary,
            )
            if (processing) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(color = Accent, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text(processingStage?.displayName ?: "Processing", color = TextSecondary)
                }
            }
            error?.let {
                Text(it, color = com.paperorg.notes.ui.theme.Error, fontSize = 14.sp)
                TextButton(onClick = onDismissError) { Text("Dismiss") }
            }
            if (note.status == "failed") {
                Text(note.errorMessage ?: "Processing failed.", color = com.paperorg.notes.ui.theme.Error)
            }
            if (hasAudio) {
                ChipSection("Language for this audio", enabled = !processing) {
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
                    "Wrong language is the usual reason a transcript looks like junk. Pick what you spoke, then transcribe again.",
                    color = TextSecondary,
                    fontSize = 12.sp,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { onRetry(retryLanguage) },
                        enabled = !processing,
                        colors = ButtonDefaults.buttonColors(containerColor = Primary),
                    ) { Text("Transcribe again") }
                    TextButton(onClick = onPlay, enabled = !processing) {
                        Text(if (playing) "Stop audio" else "Play audio")
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(
                    onClick = onResummarize,
                    enabled = !processing && transcript.isNotBlank(),
                ) { Text("Re-summarize") }
                TextButton(
                    onClick = {
                        emailResult = null
                        onSendEmail { result -> emailResult = result }
                    },
                    enabled = !processing,
                ) { Text("Send email") }
            }
            emailResult?.let {
                Text(it, color = TextSecondary, fontSize = 13.sp)
            }
            TabRow(selectedTabIndex = detailTab, containerColor = Surface, contentColor = Primary) {
                Tab(selected = detailTab == 0, onClick = { detailTab = 0 }, text = { Text("Transcript") })
                Tab(selected = detailTab == 1, onClick = { detailTab = 1 }, text = { Text("Summary") })
                Tab(selected = detailTab == 2, onClick = { detailTab = 2 }, text = { Text("Actions") })
            }
            when (detailTab) {
                0 -> {
                    if (transcript.isBlank()) {
                        Text("No transcript yet.", color = TextSecondary)
                        if (hasAudio) {
                            Text(
                                "If you already recorded this, tap Transcribe again. Older notes may have stored JSON instead of the spoken words.",
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
                        Text("No summary yet.", color = TextSecondary)
                    } else {
                        Text("Summary", fontWeight = FontWeight.SemiBold)
                        Text(summary)
                    }
                    note.summaryDetailed?.takeIf { it.isNotBlank() && it != note.summaryShort }?.let {
                        Text("Detail", fontWeight = FontWeight.SemiBold)
                        Text(it)
                    }
                    structured?.let { output ->
                        NoteListSection("Key ideas", output.keyIdeas)
                        NoteListSection("Decisions", output.decisions)
                        NoteListSection("Open questions", output.openQuestions)
                    }
                }
                else -> {
                    structured?.let { output ->
                        NoteListSection("Actions", output.actionItems)
                    } ?: Text("No action items yet.", color = TextSecondary)
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

