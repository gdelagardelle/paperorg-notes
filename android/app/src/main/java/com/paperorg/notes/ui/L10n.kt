package com.paperorg.notes.ui

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.paperorg.notes.R
import com.paperorg.notes.data.RecordingState
import com.paperorg.notes.domain.EmailContent
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.domain.ProcessingStage
import com.paperorg.notes.domain.SummaryLength

@Composable
fun OutputType.label(): String = stringResource(outputString(this))

@Composable
fun ProcessingStage.label(): String = stringResource(stageString(this))

@Composable
fun SummaryLength.label(): String = stringResource(
    when (this) {
        SummaryLength.Short -> R.string.summary_short
        SummaryLength.Detailed -> R.string.summary_detailed
    },
)

@Composable
fun EmailContent.label(): String = stringResource(
    when (this) {
        EmailContent.SummaryOnly -> R.string.email_content_summary
        EmailContent.FullTranscript -> R.string.email_content_transcript
        EmailContent.Both -> R.string.email_content_both
    },
)

@Composable
fun RecordingState.statusLabel(): String = stringResource(
    when (this) {
        RecordingState.Idle -> R.string.record_status_idle
        RecordingState.Recording -> R.string.record_status_recording
        RecordingState.Paused -> R.string.record_status_paused
    },
)

@StringRes
fun outputString(type: OutputType): Int = when (type) {
    OutputType.Meeting -> R.string.output_meeting
    OutputType.Brainstorm -> R.string.output_brainstorm
    OutputType.Memo -> R.string.output_memo
    OutputType.ClientCall -> R.string.output_client_call
    OutputType.Interview -> R.string.output_interview
    OutputType.TaskList -> R.string.output_task_list
    OutputType.Resume -> R.string.output_resume
    OutputType.Raw -> R.string.output_raw
}

@StringRes
fun stageString(stage: ProcessingStage): Int = when (stage) {
    ProcessingStage.Saving -> R.string.stage_saving
    ProcessingStage.Transcribing -> R.string.stage_transcribing
    ProcessingStage.Checking -> R.string.stage_checking
    ProcessingStage.Summarizing -> R.string.stage_summarizing
    ProcessingStage.Ready -> R.string.stage_ready
}

@StringRes
fun noteStatusString(status: String): Int = when (status) {
    "ready" -> R.string.status_ready
    "processing" -> R.string.status_processing
    "failed" -> R.string.status_failed
    "waitingfornetwork", "waiting_for_network" -> R.string.status_waiting
    else -> R.string.status_draft
}

@Composable
fun retentionLabel(days: Int): String = stringResource(
    when (days) {
        7 -> R.string.retention_7
        30 -> R.string.retention_30
        90 -> R.string.retention_90
        else -> R.string.retention_never
    },
)
