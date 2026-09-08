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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.paperorg.notes.BuildConfig
import com.paperorg.notes.R
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
import com.paperorg.notes.ui.theme.destructiveTextButtonColors
import com.paperorg.notes.ui.theme.notesSwitchColors
import com.paperorg.notes.ui.theme.textButtonColors

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
        Text(stringResource(R.string.settings_title), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Primary, modifier = Modifier.padding(top = 8.dp, bottom = 12.dp))

        SettingsSection(stringResource(R.string.settings_section_plan)) {
            if (isPro) {
                Text(stringResource(R.string.settings_pro_active), fontWeight = FontWeight.SemiBold, color = Accent, modifier = Modifier.padding(16.dp))
            } else {
                Text(stringResource(R.string.settings_free_title), fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp))
                SettingsHint(stringResource(R.string.settings_free_hint))
            }
            usage?.let {
                Text(
                    stringResource(R.string.usage_minutes_left, it.minutesRemaining, it.minutesLimit),
                    color = TextSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
                )
                it.maxRecordingMinutes?.let { cap ->
                    Text(
                        stringResource(R.string.usage_cap, cap),
                        color = TextSecondary,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
                    )
                }
            }
            if (isPro) {
                HorizontalDivider(color = Border)
                TextButton(
                    onClick = { uri.openUri(BillingRepository.manageSubscriptionsUrl(context.packageName)) },
                    modifier = Modifier.padding(horizontal = 8.dp),
                    colors = textButtonColors(),
                ) { Text(stringResource(R.string.settings_manage_play)) }
            } else {
                plans.forEach { plan ->
                    HorizontalDivider(color = Border)
                    Row(
                        Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.settings_pro_period, plan.period), color = Primary, fontSize = 13.sp)
                            Text(stringResource(R.string.settings_pro_price, plan.price, plan.period), color = TextSecondary, fontSize = 12.sp)
                        }
                        TextButton(
                            onClick = { activity?.let { model.buyPro(it, plan) } },
                            enabled = activity != null,
                            colors = textButtonColors(),
                        ) { Text(stringResource(R.string.settings_subscribe)) }
                    }
                }
                if (plans.isEmpty()) {
                    SettingsHint(stringResource(R.string.settings_plans_missing))
                }
                HorizontalDivider(color = Border)
                TextButton(
                    onClick = { model.restorePurchases() },
                    modifier = Modifier.padding(horizontal = 8.dp),
                    colors = textButtonColors(),
                ) { Text(stringResource(R.string.settings_restore)) }
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
                    if (connected) stringResource(R.string.settings_connected, settings.deviceId.take(8))
                    else stringResource(R.string.settings_not_connected),
                    color = TextSecondary,
                    fontSize = 12.sp,
                )
            }
        }

        SettingsSection(stringResource(R.string.settings_section_language)) {
            SettingsMenu(
                label = stringResource(R.string.settings_default_language),
                value = "${language.flag} ${language.displayName}",
                options = AppLanguage.spoken.map { it.code to "${it.flag} ${it.displayName}" },
                onSelect = { code ->
                    val next = AppLanguage.fromCode(code)
                    language = next
                    model.setLanguage(next)
                },
            )
        }

        SettingsSection(stringResource(R.string.settings_section_vocabulary)) {
            Text(stringResource(R.string.settings_vocab_title), fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp))
            SettingsHint(stringResource(R.string.settings_vocab_hint))
            if (!isPro) {
                SettingsHint(stringResource(R.string.settings_vocab_free_hint, settings.freeVocabularyLimit))
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
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.common_remove), tint = TextSecondary)
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
                    placeholder = { Text(stringResource(R.string.settings_vocab_add), fontSize = 13.sp) },
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
                    colors = textButtonColors(),
                ) { Text(stringResource(R.string.common_add)) }
            }
        }

        SettingsSection(stringResource(R.string.settings_section_output)) {
            SettingsMenu(
                label = stringResource(R.string.settings_output_type),
                value = output.label(),
                options = OutputType.entries.map { it.code to it.label() },
                onSelect = { code ->
                    val next = OutputType.entries.find { it.code == code } ?: OutputType.Meeting
                    output = next
                    model.setOutput(next)
                },
            )
            HorizontalDivider(color = Border)
            SettingsMenu(
                label = stringResource(R.string.settings_summary_length),
                value = summary.label(),
                options = SummaryLength.entries.map { it.code to it.label() },
                onSelect = { code ->
                    val next = SummaryLength.fromCode(code)
                    summary = next
                    model.setSummaryLength(next.code)
                },
            )
        }

        EmailSettingsSection(model)

        SettingsSection(stringResource(R.string.settings_section_privacy)) {
            SettingsToggle(stringResource(R.string.settings_keep_audio), keepAudio) {
                keepAudio = it
                settings.keepAudio = it
            }
            if (keepAudio) {
                HorizontalDivider(color = Border)
                SettingsToggle(stringResource(R.string.settings_delete_after_tx), deleteAudio) {
                    deleteAudio = it
                    settings.deleteAudioAfterTranscription = it
                }
                if (deleteAudio) {
                    SettingsHint(stringResource(R.string.settings_delete_after_tx_hint))
                } else {
                    HorizontalDivider(color = Border)
                    SettingsMenu(
                        label = stringResource(R.string.settings_delete_after),
                        value = retentionLabel(retentionDays),
                        options = listOf(
                            0 to stringResource(R.string.retention_never),
                            7 to stringResource(R.string.retention_7),
                            30 to stringResource(R.string.retention_30),
                            90 to stringResource(R.string.retention_90),
                        ).map { it.first.toString() to it.second },
                        onSelect = { code ->
                            val days = code.toInt()
                            retentionDays = days
                            settings.deleteAudioAfterDays = days
                        },
                    )
                }
            } else {
                SettingsHint(stringResource(R.string.settings_audio_off_hint))
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
                    context.startActivity(Intent.createChooser(share, context.getString(R.string.chooser_export)))
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                colors = textButtonColors(),
            ) { Text(stringResource(R.string.settings_export_all)) }
            TextButton(
                onClick = { confirmDelete = true },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                colors = destructiveTextButtonColors(),
            ) { Text(stringResource(R.string.settings_delete_all)) }
        }

        SettingsSection(stringResource(R.string.settings_section_howto)) {
            SettingsHint(stringResource(R.string.howto_record))
            SettingsHint(stringResource(R.string.howto_import))
            SettingsHint(stringResource(R.string.howto_free))
            SettingsHint(stringResource(R.string.howto_pro))
        }

        SettingsSection(stringResource(R.string.settings_section_about)) {
            SettingsValueRow(stringResource(R.string.about_version), BuildConfig.VERSION_NAME)
            HorizontalDivider(color = Border)
            Text(stringResource(R.string.about_providers), fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp))
            SettingsHint(stringResource(R.string.about_lux_path))
            SettingsHint(stringResource(R.string.about_other_path))
            Text(stringResource(R.string.about_luxasr_title), fontWeight = FontWeight.SemiBold, color = Primary, modifier = Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp))
            SettingsHint(stringResource(R.string.about_luxasr_credit))
            TextButton(
                onClick = { uri.openUri("https://luxasr.uni.lu") },
                modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
                colors = textButtonColors(),
            ) {
                Text("luxasr.uni.lu")
            }
        }

        SettingsSection(stringResource(R.string.settings_section_testing)) {
            SettingsToggle(stringResource(R.string.settings_luxasr_toggle), luxAsr) {
                luxAsr = it
                settings.luxAsrEnabled = it
            }
            SettingsHint(stringResource(R.string.settings_luxasr_hint))
            Spacer(Modifier.height(8.dp))
        }

        Spacer(Modifier.height(24.dp))
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.settings_delete_all_title)) },
            text = { Text(stringResource(R.string.settings_delete_all_body)) },
            confirmButton = {
                TextButton(
                    onClick = { model.deleteAll(); confirmDelete = false },
                    colors = destructiveTextButtonColors(),
                ) { Text(stringResource(R.string.settings_delete_everything)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }, colors = textButtonColors()) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
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

    SettingsSection(stringResource(R.string.settings_section_email)) {
        SettingsToggle(stringResource(R.string.email_send_after), sendAfter) {
            sendAfter = it
            settings.sendEmailAfterTranscription = it
        }
        if (sendAfter) {
            SettingsHint(stringResource(R.string.email_send_after_hint))
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
                            stringResource(R.string.email_sends_as, from)
                        }
                        checkingStatus -> stringResource(R.string.email_checking)
                        else -> stringResource(R.string.email_server_fallback)
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
                placeholder = { Text(stringResource(R.string.email_add_address), fontSize = 13.sp) },
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
                colors = textButtonColors(),
            ) { Text(stringResource(R.string.common_add)) }
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
                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.common_remove), tint = TextSecondary)
                }
            }
        }
        HorizontalDivider(color = Border)
        SettingsMenu(
            label = stringResource(R.string.email_content),
            value = content.label(),
            options = EmailContent.entries.map { it.code to it.label() },
            onSelect = { code ->
                val next = EmailContent.fromCode(code)
                content = next
                settings.emailContent = next.code
            },
        )
        HorizontalDivider(color = Border)
        SettingsToggle(stringResource(R.string.email_attach_audio), attachAudio) {
            attachAudio = it
            settings.emailAttachAudio = it
        }
        HorizontalDivider(color = Border)
        SettingsToggle(stringResource(R.string.email_attach_pdf), attachPdf) {
            attachPdf = it
            settings.emailAttachPDF = it
        }
        HorizontalDivider(color = Border)
        SettingsToggle(stringResource(R.string.email_attach_markdown), attachMarkdown) {
            attachMarkdown = it
            settings.emailAttachMarkdown = it
        }
        HorizontalDivider(color = Border)
        SettingsToggle(stringResource(R.string.email_review), reviewBefore) {
            reviewBefore = it
            settings.reviewBeforeEmail = it
        }
        if (reviewBefore) {
            SettingsHint(stringResource(R.string.email_review_hint))
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
                placeholder = { Text(stringResource(R.string.email_test_address), fontSize = 13.sp) },
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
                colors = textButtonColors(),
            ) { Text(if (sendingTest) stringResource(R.string.email_sending) else stringResource(R.string.email_send_test)) }
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
            colors = notesSwitchColors(),
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
