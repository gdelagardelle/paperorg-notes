package com.paperorg.notes.ui

import android.app.Activity
import android.content.Intent
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.paperorg.notes.BuildConfig
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.EmailContent
import com.paperorg.notes.domain.EmailServerStatus
import com.paperorg.notes.data.BillingRepository
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.domain.SummaryLength
import com.paperorg.notes.domain.UsageInfo
import com.paperorg.notes.ui.theme.Accent
import com.paperorg.notes.ui.theme.Background
import com.paperorg.notes.ui.theme.Border
import com.paperorg.notes.ui.theme.Error
import com.paperorg.notes.ui.theme.Primary
import com.paperorg.notes.ui.theme.Surface
import com.paperorg.notes.ui.theme.TextSecondary

@Composable
fun SettingsScreen(model: AppViewModel, notes: List<Note>, usage: UsageInfo?) {
    val context = LocalContext.current
    val activity = context as? Activity
    val uri = LocalUriHandler.current
    val settings = model.settings
    val plans by model.plans.collectAsState()
    val billingMessage by model.billingMessage.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    var keepAudio by remember { mutableStateOf(settings.keepAudio) }
    var deleteAudio by remember { mutableStateOf(settings.deleteAudioAfterTranscription) }
    var luxAsr by remember { mutableStateOf(settings.luxAsrEnabled) }
    var language by remember { mutableStateOf(AppLanguage.fromCode(settings.defaultLanguage)) }
    var output by remember {
        mutableStateOf(OutputType.entries.find { it.code == settings.defaultOutputType } ?: OutputType.Meeting)
    }
    var summary by remember { mutableStateOf(SummaryLength.fromCode(settings.summaryLength)) }
    var retentionDays by remember { mutableStateOf(settings.deleteAudioAfterDays) }
    var terms by remember { mutableStateOf(settings.customVocabulary) }
    var newTerm by remember { mutableStateOf("") }
    val isPro = usage?.isPro == true

    LaunchedEffect(notes) { model.purgeExpiredAudio(notes) }

    Column(
        Modifier
            .fillMaxSize()
            .background(Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 8.dp),
    ) {
        Text("Settings", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Primary, modifier = Modifier.padding(top = 8.dp, bottom = 12.dp))

        SettingsSection("Plan") {
            if (isPro) {
                Text("Paperorg Pro is active", fontWeight = FontWeight.SemiBold, color = Accent, modifier = Modifier.padding(16.dp))
            } else {
                Text("Included minutes", fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp))
                SettingsHint("Free includes 30 minutes of cloud transcription and AI summaries each month. No API keys or sign-in required.")
            }
            usage?.let {
                Text(
                    "${"%.1f".format(it.minutesRemaining)} of ${it.minutesLimit} minutes left this month",
                    color = TextSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
                )
            }
            if (isPro) {
                HorizontalDivider(color = Border)
                TextButton(
                    onClick = { uri.openUri(BillingRepository.manageSubscriptionsUrl(context.packageName)) },
                    modifier = Modifier.padding(horizontal = 8.dp),
                ) { Text("Manage subscription in Google Play") }
            } else {
                plans.forEach { plan ->
                    HorizontalDivider(color = Border)
                    Row(
                        Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Pro, billed per ${plan.period}", color = Primary, fontSize = 13.sp)
                            Text("${plan.price} / ${plan.period}", color = TextSecondary, fontSize = 12.sp)
                        }
                        TextButton(
                            onClick = { activity?.let { model.buyPro(it, plan) } },
                            enabled = activity != null,
                        ) { Text("Subscribe") }
                    }
                }
                if (plans.isEmpty()) {
                    SettingsHint(
                        "Paperorg Pro is not offered by Google Play on this device yet. " +
                            "It appears once the app is installed from Play with the subscription live.",
                    )
                }
                HorizontalDivider(color = Border)
                TextButton(
                    onClick = { model.restorePurchases() },
                    modifier = Modifier.padding(horizontal = 8.dp),
                ) { Text("Restore purchase") }
            }
            billingMessage?.let { message ->
                Text(
                    message,
                    color = if (message.contains("active") || message.contains("restored")) Accent else TextSecondary,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                )
            }
            val connected = settings.accessToken != null
            Row(
                Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(Modifier.size(10.dp).clip(CircleShape).background(if (connected) Color(0xFF2E9E5B) else Border))
                Text(
                    if (connected) "Connected · device ${settings.deviceId.take(8)}"
                    else "Not connected — connects automatically on first transcription",
                    color = TextSecondary,
                    fontSize = 12.sp,
                )
            }
        }

        SettingsSection("Language") {
            SettingsMenu(
                label = "Default language",
                value = "${language.flag} ${language.displayName}",
                options = AppLanguage.spoken.map { it.code to "${it.flag} ${it.displayName}" },
                onSelect = { code ->
                    val next = AppLanguage.fromCode(code)
                    language = next
                    model.setLanguage(next)
                },
            )
        }

        SettingsSection("Vocabulary") {
            Text("Custom vocabulary", fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp))
            SettingsHint("Names, brands, and terms to improve transcription accuracy.")
            if (!isPro) {
                SettingsHint("Free plan: up to ${settings.freeVocabularyLimit} terms. Pro includes unlimited vocabulary.")
            }
            terms.forEach { term ->
                HorizontalDivider(color = Border)
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(term, modifier = Modifier.weight(1f), color = Primary)
                    IconButton(onClick = {
                        settings.removeVocabularyTerm(term)
                        terms = settings.customVocabulary
                    }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Remove", tint = TextSecondary)
                    }
                }
            }
            HorizontalDivider(color = Border)
            Row(
                Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = newTerm,
                    onValueChange = { newTerm = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Add term", fontSize = 13.sp) },
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 13.sp, color = Primary),
                )
                TextButton(
                    onClick = {
                        if (settings.addVocabularyTerm(newTerm, isPro)) {
                            terms = settings.customVocabulary
                            newTerm = ""
                        }
                    },
                    enabled = newTerm.trim().isNotEmpty() && (isPro || terms.size < settings.freeVocabularyLimit),
                ) { Text("Add") }
            }
        }

        SettingsSection("Output") {
            SettingsMenu(
                label = "Default output type",
                value = output.displayName,
                options = OutputType.entries.map { it.code to it.displayName },
                onSelect = { code ->
                    val next = OutputType.entries.find { it.code == code } ?: OutputType.Meeting
                    output = next
                    model.setOutput(next)
                },
            )
            HorizontalDivider(color = Border)
            SettingsMenu(
                label = "Summary length",
                value = summary.displayName,
                options = SummaryLength.entries.map { it.code to it.displayName },
                onSelect = { code ->
                    val next = SummaryLength.fromCode(code)
                    summary = next
                    model.setSummaryLength(next.code)
                },
            )
        }

        EmailSettingsSection(model)

        SettingsSection("Privacy & GDPR") {
            SettingsToggle("Keep audio files", keepAudio) {
                keepAudio = it
                settings.keepAudio = it
            }
            if (keepAudio) {
                HorizontalDivider(color = Border)
                SettingsToggle("Delete audio after transcription", deleteAudio) {
                    deleteAudio = it
                    settings.deleteAudioAfterTranscription = it
                }
                if (deleteAudio) {
                    SettingsHint("Audio is removed as soon as transcription completes.")
                } else {
                    HorizontalDivider(color = Border)
                    SettingsMenu(
                        label = "Delete audio after",
                        value = retentionLabel(retentionDays),
                        options = listOf(0 to "Never", 7 to "7 days", 30 to "30 days", 90 to "90 days").map { it.first.toString() to it.second },
                        onSelect = { code ->
                            val days = code.toInt()
                            retentionDays = days
                            settings.deleteAudioAfterDays = days
                        },
                    )
                }
            } else {
                SettingsHint("Audio is removed after transcription. Retention options are unavailable.")
            }
            HorizontalDivider(color = Border)
            TextButton(
                onClick = {
                    val file = model.gdpr.export(notes)
                    val shareUri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                    val share = Intent(Intent.ACTION_SEND).apply {
                        type = "application/zip"
                        putExtra(Intent.EXTRA_STREAM, shareUri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(Intent.createChooser(share, "Export notes"))
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            ) { Text("Export all data") }
            TextButton(
                onClick = { confirmDelete = true },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                colors = ButtonDefaults.textButtonColors(contentColor = Error),
            ) { Text("Delete all data") }
        }

        SettingsSection("About") {
            SettingsValueRow("Version", BuildConfig.VERSION_NAME)
            HorizontalDivider(color = Border)
            Text("Transcription providers", fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp))
            SettingsHint("Luxembourgish: LuxASR (primary) → ElevenLabs → OpenAI")
            SettingsHint("Other languages: OpenAI (primary) → ElevenLabs")
            Text("Lëtzebuergesch transcription", fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp))
            SettingsHint("Powered by LuxASR, developed at the University of Luxembourg.")
            TextButton(onClick = { uri.openUri("https://luxasr.uni.lu") }, modifier = Modifier.padding(start = 4.dp, bottom = 8.dp)) {
                Text("luxasr.uni.lu")
            }
        }

        SettingsSection("Testing") {
            SettingsToggle("Use LuxASR for Lëtzebuergesch", luxAsr) {
                luxAsr = it
                settings.luxAsrEnabled = it
            }
            SettingsHint("Off sends Lëtzebuergesch to ElevenLabs instead, so the two can be compared on the same recording.")
            Spacer(Modifier.height(8.dp))
        }

        Spacer(Modifier.height(24.dp))
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete all data?") },
            text = { Text("This permanently deletes all notes, audio, transcripts, and local settings on this device.") },
            confirmButton = {
                TextButton(onClick = { model.deleteAll(); confirmDelete = false }) { Text("Delete everything") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun EmailSettingsSection(model: AppViewModel) {
    val settings = model.settings
    var sendAfter by remember { mutableStateOf(settings.sendEmailAfterTranscription) }
    var recipients by remember { mutableStateOf(settings.emailRecipients) }
    var newEmail by remember { mutableStateOf("") }
    var validation by remember { mutableStateOf<String?>(null) }
    var content by remember { mutableStateOf(EmailContent.fromCode(settings.emailContent)) }
    var attachAudio by remember { mutableStateOf(settings.emailAttachAudio) }
    var attachPdf by remember { mutableStateOf(settings.emailAttachPDF) }
    var attachMarkdown by remember { mutableStateOf(settings.emailAttachMarkdown) }
    var reviewBefore by remember { mutableStateOf(settings.reviewBeforeEmail) }
    var testAddress by remember { mutableStateOf("") }
    var sendingTest by remember { mutableStateOf(false) }
    var testResult by remember { mutableStateOf<String?>(null) }
    var serverStatus by remember { mutableStateOf<EmailServerStatus?>(null) }
    var checkingStatus by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        serverStatus = model.emailStatus()
        checkingStatus = false
    }

    SettingsSection("Email") {
        SettingsToggle("Send email after transcription", sendAfter) {
            sendAfter = it
            settings.sendEmailAfterTranscription = it
        }
        if (sendAfter) {
            SettingsHint("Paperorg can send your note automatically when transcription finishes. Add who should receive it below.")
            Row(
                Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    Modifier.size(10.dp).clip(CircleShape).background(
                        if (serverStatus?.available == true) Color(0xFF2E9E5B) else Border,
                    ),
                )
                Text(
                    when {
                        serverStatus?.available == true -> {
                            val from = listOfNotNull(
                                serverStatus?.fromName,
                                serverStatus?.fromAddress?.let { "<$it>" },
                            ).joinToString(" ").ifBlank { "Paperorg" }
                            "Sends as $from"
                        }
                        checkingStatus -> "Checking server email…"
                        else -> "Paperorg sends from the server. Add who should receive it below."
                    },
                    color = TextSecondary,
                    fontSize = 12.sp,
                )
            }
        }
        HorizontalDivider(color = Border)
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = newEmail,
                onValueChange = {
                    newEmail = it
                    validation = null
                },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Add email address", fontSize = 13.sp) },
                singleLine = true,
                textStyle = TextStyle(fontSize = 13.sp, color = Primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            )
            TextButton(
                onClick = {
                    val error = settings.addEmailRecipient(newEmail)
                    if (error == null) {
                        recipients = settings.emailRecipients
                        newEmail = ""
                        validation = null
                    } else {
                        validation = error
                    }
                },
                enabled = newEmail.trim().isNotEmpty(),
            ) { Text("Add") }
        }
        validation?.let {
            Text(it, color = Error, fontSize = 12.sp, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp))
        }
        recipients.forEach { email ->
            HorizontalDivider(color = Border)
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(email, modifier = Modifier.weight(1f), color = Primary, fontSize = 14.sp)
                IconButton(onClick = {
                    settings.removeEmailRecipient(email)
                    recipients = settings.emailRecipients
                }) {
                    Icon(Icons.Filled.Delete, contentDescription = "Remove", tint = TextSecondary)
                }
            }
        }
        HorizontalDivider(color = Border)
        SettingsMenu(
            label = "Content",
            value = content.displayName,
            options = EmailContent.entries.map { it.code to it.displayName },
            onSelect = { code ->
                val next = EmailContent.fromCode(code)
                content = next
                settings.emailContent = next.code
            },
        )
        HorizontalDivider(color = Border)
        SettingsToggle("Attach audio", attachAudio) {
            attachAudio = it
            settings.emailAttachAudio = it
        }
        HorizontalDivider(color = Border)
        SettingsToggle("Attach PDF", attachPdf) {
            attachPdf = it
            settings.emailAttachPDF = it
        }
        if (attachPdf) {
            SettingsHint("PDF export is not on Android yet. The other attachments still go out.")
        }
        HorizontalDivider(color = Border)
        SettingsToggle("Attach Markdown", attachMarkdown) {
            attachMarkdown = it
            settings.emailAttachMarkdown = it
        }
        HorizontalDivider(color = Border)
        SettingsToggle("Review before send", reviewBefore) {
            reviewBefore = it
            settings.reviewBeforeEmail = it
        }
        if (reviewBefore) {
            SettingsHint("Only applies when you tap Send email on a note. Automatic post-recording email always sends without review.")
        }
        HorizontalDivider(color = Border)
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = testAddress,
                onValueChange = { testAddress = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Test address", fontSize = 13.sp) },
                singleLine = true,
                textStyle = TextStyle(fontSize = 13.sp, color = Primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            )
            TextButton(
                onClick = {
                    sendingTest = true
                    testResult = null
                    model.sendTestEmail(
                        address = testAddress,
                        onResult = { result ->
                            sendingTest = false
                            testResult = result
                        },
                    )
                },
                enabled = !sendingTest && testAddress.trim().isNotEmpty(),
            ) { Text(if (sendingTest) "Sending…" else "Send test") }
        }
        testResult?.let {
            Text(
                it,
                color = if (it.startsWith("✓")) Color(0xFF2E9E5B) else TextSecondary,
                fontSize = 12.sp,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
            )
        }
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Text(
        title.uppercase(),
        color = TextSecondary,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 4.dp, bottom = 8.dp, top = 12.dp),
    )
    Card(
        colors = CardDefaults.cardColors(containerColor = Surface),
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
    ) {
        Column { content() }
    }
}

@Composable
private fun SettingsHint(text: String) {
    Text(text, color = TextSecondary, fontSize = 11.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
}

@Composable
private fun SettingsToggle(title: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f), color = Primary, fontSize = 13.sp)
        Switch(
            checked = checked,
            onCheckedChange = onChecked,
            colors = SwitchDefaults.colors(checkedTrackColor = Accent, checkedThumbColor = Color.White),
        )
    }
}

@Composable
private fun SettingsValueRow(label: String, value: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f), color = Primary)
        Text(value, color = TextSecondary)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsMenu(
    label: String,
    value: String,
    options: List<Pair<String, String>>,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Text(label, color = TextSecondary, fontSize = 12.sp, modifier = Modifier.padding(bottom = 6.dp))
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
            OutlinedTextField(
                value = value,
                onValueChange = {},
                readOnly = true,
                textStyle = TextStyle(fontSize = 13.sp, color = Primary),
                modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { (id, title) ->
                    DropdownMenuItem(
                        text = { Text(title) },
                        onClick = {
                            onSelect(id)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

private fun retentionLabel(days: Int): String = when (days) {
    7 -> "7 days"
    30 -> "30 days"
    90 -> "90 days"
    else -> "Never"
}
