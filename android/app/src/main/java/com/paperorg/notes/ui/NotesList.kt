package com.paperorg.notes.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.DurationFormat
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.ui.theme.Accent
import com.paperorg.notes.ui.theme.Border
import com.paperorg.notes.ui.theme.Primary
import com.paperorg.notes.ui.theme.Surface
import com.paperorg.notes.ui.theme.TextSecondary
import java.text.DateFormat
import java.util.Date

@Composable
fun NotesScreen(notes: List<Note>, onOpen: (Note) -> Unit, onDelete: (Note) -> Unit) {
    var favoritesOnly by remember { mutableStateOf(false) }
    var filterLanguage by remember { mutableStateOf<AppLanguage?>(null) }
    var filterMenu by remember { mutableStateOf(false) }
    val filtered = notes.filter { note ->
        if (favoritesOnly && !note.isFavorite) return@filter false
        if (filterLanguage != null && note.language != filterLanguage!!.code) return@filter false
        true
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        Row(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Notes", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Primary, modifier = Modifier.weight(1f))
            Box {
                IconButton(onClick = { filterMenu = true }) {
                    Icon(Icons.Filled.FilterList, contentDescription = "Filters", tint = Primary)
                }
                DropdownMenu(expanded = filterMenu, onDismissRequest = { filterMenu = false }) {
                    DropdownMenuItem(
                        text = { Text(if (favoritesOnly) "All notes" else "Favorites only") },
                        onClick = {
                            favoritesOnly = !favoritesOnly
                            filterMenu = false
                        },
                    )
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("All languages") },
                        onClick = {
                            filterLanguage = null
                            filterMenu = false
                        },
                    )
                    AppLanguage.spoken.forEach { language ->
                        DropdownMenuItem(
                            text = { Text("${language.flag} ${language.displayName}") },
                            onClick = {
                                filterLanguage = language
                                filterMenu = false
                            },
                        )
                    }
                }
            }
        }
        val filtersActive = favoritesOnly || filterLanguage != null
        if (filtersActive) {
            Text("FILTERS", color = TextSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (favoritesOnly) {
                    SelectionChip(title = "Favorites", selected = true, enabled = true) { favoritesOnly = false }
                }
                filterLanguage?.let { language ->
                    SelectionChip(
                        title = "${language.flag} ${language.displayName}",
                        selected = true,
                        enabled = true,
                    ) { filterLanguage = null }
                }
            }
        }
        when {
            notes.isEmpty() -> EmptyLibrary()
            filtered.isEmpty() -> NoMatchCard()
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(bottom = 24.dp)) {
                items(filtered, key = { it.id }) { note ->
                    SwipeDeleteNote(onDelete = { onDelete(note) }) {
                        NoteCard(note, onOpen = { onOpen(note) })
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyLibrary() {
    Column(
        Modifier.fillMaxWidth().padding(top = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.Description, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(40.dp))
        Text("No notes yet", fontWeight = FontWeight.SemiBold, color = Primary)
        Text("Record something from the Record tab to build your library.", color = TextSecondary, fontSize = 14.sp)
    }
}

@Composable
private fun NoMatchCard() {
    Card(
        colors = CardDefaults.cardColors(containerColor = Surface),
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(1.dp, Border),
        shape = RoundedCornerShape(20.dp),
    ) {
        Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Filled.FilterList, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(36.dp))
            Spacer(Modifier.height(8.dp))
            Text("No matching notes", fontWeight = FontWeight.SemiBold, color = Primary)
            Text("Try clearing a filter or recording something new.", color = TextSecondary, fontSize = 14.sp)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeDeleteNote(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                true
            } else {
                false
            }
        },
    )
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().clip(RoundedCornerShape(20.dp)).background(com.paperorg.notes.ui.theme.Error),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(Icons.Filled.Delete, contentDescription = "Delete", tint = Color.White, modifier = Modifier.padding(end = 20.dp))
            }
        },
        content = { content() },
    )
}

@Composable
fun NoteCard(note: Note, onOpen: () -> Unit, compact: Boolean = false) {
    val stripe = when (note.status) {
        "ready" -> Primary
        "processing" -> Accent
        "failed" -> com.paperorg.notes.ui.theme.Error
        "waitingfornetwork", "waiting_for_network" -> Color(0xFFE0A106)
        else -> Border
    }
    val language = AppLanguage.fromCode(note.language)
    val output = OutputType.entries.find { it.code == note.outputType }?.displayName
    Card(
        colors = CardDefaults.cardColors(containerColor = Surface),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(1.dp, Border),
        shape = RoundedCornerShape(20.dp),
    ) {
        Row(Modifier.height(IntrinsicSize.Min).padding(if (compact) 14.dp else 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(4.dp).fillMaxHeight().clip(RoundedCornerShape(3.dp)).background(stripe))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        note.title,
                        fontWeight = FontWeight.Bold,
                        color = Primary,
                        fontSize = if (compact) 14.sp else 16.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    if (note.isFavorite) {
                        Icon(Icons.Filled.Star, contentDescription = null, tint = Accent, modifier = Modifier.size(14.dp).padding(end = 6.dp))
                    }
                    NoteStatusBadge(note.status, compact)
                }
                Text(
                    "${language.flag}  ·  ${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(note.createdAtMillis))}  ·  ${DurationFormat.format(note.durationSeconds)}",
                    color = TextSecondary,
                    fontSize = 12.sp,
                )
                if (compact && output != null) {
                    Text(output, color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                } else {
                    note.previewSnippet.takeIf { it.isNotBlank() }?.let {
                        Text(it, color = TextSecondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun NoteStatusBadge(status: String, compact: Boolean) {
    val color = when (status) {
        "ready" -> Primary
        "processing" -> Accent
        "failed" -> com.paperorg.notes.ui.theme.Error
        "waitingfornetwork", "waiting_for_network" -> Color(0xFFE0A106)
        else -> TextSecondary
    }
    val label = when (status) {
        "ready" -> "Ready"
        "processing" -> "Processing"
        "failed" -> "Failed"
        "waitingfornetwork", "waiting_for_network" -> "Waiting"
        else -> "Draft"
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = if (compact) Modifier else Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    ) {
        when (status) {
            "processing" -> CircularProgressIndicator(color = color, modifier = Modifier.size(12.dp), strokeWidth = 1.5.dp)
            "ready" -> Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = color, modifier = Modifier.size(12.dp))
            "failed" -> Icon(Icons.Filled.Error, contentDescription = null, tint = color, modifier = Modifier.size(12.dp))
            "waitingfornetwork", "waiting_for_network" -> Icon(Icons.Filled.WifiOff, contentDescription = null, tint = color, modifier = Modifier.size(12.dp))
            else -> Icon(Icons.Outlined.Circle, contentDescription = null, tint = color, modifier = Modifier.size(12.dp))
        }
        if (!compact) {
            Text(label, color = color, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}
