import Foundation

enum L10n {
    enum Tab {
        static let record = String(localized: "tab.record")
        static let notes = String(localized: "tab.notes")
        static let search = String(localized: "tab.search")
        static let settings = String(localized: "tab.settings")
    }

    enum Settings {
        static let title = String(localized: "settings.title")
        static let proSection = String(localized: "settings.pro.section")
        static let proActive = String(localized: "settings.pro.active")
        static let proHint = String(localized: "settings.pro.hint")
        static let upgradePro = String(localized: "settings.pro.upgrade")
        static let subscribePro = String(localized: "settings.pro.subscribe")
        static let proSelected = String(localized: "settings.pro.selected")
        static let languageSection = String(localized: "settings.language.section")
        static let defaultLanguage = String(localized: "settings.language.default")
        static let autoDetectLanguage = String(localized: "settings.language.auto_detect")
        static let autoDetectLanguageHint = String(localized: "settings.language.auto_detect_hint")
        static let transcriptionSection = String(localized: "settings.transcription.section")
        static let pdfBrandingSection = String(localized: "settings.pdf.section")
        static let pdfBrandingHint = String(localized: "settings.pdf.hint")
        static let brandName = String(localized: "settings.pdf.brand_name")
        static let brandSubtitle = String(localized: "settings.pdf.brand_subtitle")
        static let uploadLogo = String(localized: "settings.pdf.upload_logo")
        static let replaceLogo = String(localized: "settings.pdf.replace_logo")
        static let useDefaultLogo = String(localized: "settings.pdf.use_default_logo")
    }

    enum Plan {
        static let chooseTitle = String(localized: "plan.choose.title")
        static let chooseSubtitle = String(localized: "plan.choose.subtitle")
        static let freePrice = String(localized: "plan.free.price")
        static let continueFree = String(localized: "plan.free.continue")
        static let getPro = String(localized: "plan.pro.get")
        static let proFallbackPrice = String(localized: "plan.pro.fallback_price")
    }

    enum Pro {
        static let usageWarning = String(localized: "pro.usage.warning")
        static let includedTranscription = String(localized: "pro.usage.included")
        static let minutesUsed = String(localized: "pro.usage.used")
        static let minutesLeft = String(localized: "pro.usage.left")
        static let monthlyQuota = String(localized: "pro.usage.quota")
        static let renews = String(localized: "pro.usage.renews")
    }

    enum Common {
        static let ok = String(localized: "common.ok")
        static let cancel = String(localized: "common.cancel")
    }

    enum Record {
        static let failedTitle = String(localized: "record.failed.title")
        static let quickRecordQueuedTitle = String(localized: "record.quick_queued.title")
        static let quickRecordQueuedMessage = String(localized: "record.quick_queued.message")
        static let language = String(localized: "record.language")
        static let noteStyle = String(localized: "record.note_style")
        static let emptyTitle = String(localized: "record.empty.title")
        static let emptySubtitle = String(localized: "record.empty.subtitle")
    }

    enum Notes {
        static let title = String(localized: "tab.notes")
        static let filters = String(localized: "notes.filters")
        static let emptyTitle = String(localized: "notes.empty.title")
        static let emptySubtitle = String(localized: "notes.empty.subtitle")
        static let noMatchTitle = String(localized: "notes.no_match.title")
        static let noMatchSubtitle = String(localized: "notes.no_match.subtitle")
    }

    enum Search {
        static let title = String(localized: "tab.search")
        static let refine = String(localized: "search.refine")
        static let emptyTitle = String(localized: "search.empty.title")
        static let emptySubtitle = String(localized: "search.empty.subtitle")
        static let noResultsTitle = String(localized: "search.no_results.title")
        static let noResultsSubtitle = String(localized: "search.no_results.subtitle")
    }

    enum Privacy {
        static let title = String(localized: "privacy.title")
        static let intro = String(localized: "privacy.intro")
        static let agree = String(localized: "privacy.agree")
        static let providerHint = String(localized: "privacy.provider_hint")
        static let viewPolicy = String(localized: "privacy.view_policy")
        static let `continue` = String(localized: "privacy.continue")
        static let rowLocalTitle = String(localized: "privacy.row.local.title")
        static let rowLocalDetail = String(localized: "privacy.row.local.detail")
        static let rowControlTitle = String(localized: "privacy.row.control.title")
        static let rowControlDetail = String(localized: "privacy.row.control.detail")
        static let rowGdprTitle = String(localized: "privacy.row.gdpr.title")
        static let rowGdprDetail = String(localized: "privacy.row.gdpr.detail")
        static let rowProvidersTitle = String(localized: "privacy.row.providers.title")
        static let rowProvidersDetail = String(localized: "privacy.row.providers.detail")
    }

    enum Lock {
        static let title = String(localized: "lock.title")
        static let unlock = String(localized: "lock.unlock")
        static let disable = String(localized: "lock.disable")
    }

    enum NoteDetail {
        static let deleteRecording = String(localized: "note.detail.delete_recording")
        static let deleteNote = String(localized: "note.detail.delete_note")
        static let deleteAudio = String(localized: "note.detail.delete_audio")
        static let delete = String(localized: "note.detail.delete")
        static let deleteRecordingTitle = String(localized: "note.detail.delete_recording.title")
        static let deleteRecordingMessage = String(localized: "note.detail.delete_recording.message")
        static let deleteNoteTitle = String(localized: "note.detail.delete_note.title")
        static let deleteNoteMessage = String(localized: "note.detail.delete_note.message")
        static let exportFailed = String(localized: "note.detail.export_failed")
        static let reprocessTitle = String(localized: "note.detail.reprocess.title")
        static let reprocessSubtitle = String(localized: "note.detail.reprocess.subtitle")
        static let noteStyle = String(localized: "note.detail.note_style")
        static let transcribeAgain = String(localized: "note.detail.transcribe_again")
        static let resummarize = String(localized: "note.detail.resummarize")
        static let audioDeletedHint = String(localized: "note.detail.audio_deleted_hint")
        static let tabTranscript = String(localized: "note.detail.tab.transcript")
        static let tabSummary = String(localized: "note.detail.tab.summary")
        static let tabActions = String(localized: "note.detail.tab.actions")
        static let noTranscript = String(localized: "note.detail.no_transcript")
        static let summaryHeader = String(localized: "note.detail.summary_header")
        static let detailed = String(localized: "note.detail.detailed")
        static let keyIdeas = String(localized: "note.detail.key_ideas")
        static let decisions = String(localized: "note.detail.decisions")
        static let openQuestions = String(localized: "note.detail.open_questions")
        static let noActionItems = String(localized: "note.detail.no_action_items")
        static let followUpEmail = String(localized: "note.detail.follow_up_email")
        static let export = String(localized: "note.detail.export")
        static let shareText = String(localized: "note.detail.share_text")
        static let shareDebug = String(localized: "note.detail.share_debug")
        static let editSegment = String(localized: "note.detail.edit_segment")
        static let save = String(localized: "note.detail.save")

        static func assignee(_ name: String) -> String {
            String(localized: "note.detail.assignee \(name)")
        }

        static func segmentUnclear(confidence: Int) -> String {
            String(localized: "note.detail.segment.unclear \(confidence)")
        }

        static func segmentConfidence(_ percent: Int) -> String {
            String(localized: "note.detail.segment.confidence \(percent)")
        }
    }

    enum Email {
        static let reviewTitle = String(localized: "email.review.title")
        static let subject = String(localized: "email.subject")
        static let message = String(localized: "email.message")
        static let send = String(localized: "email.send")
        static let reviewRecommended = String(localized: "email.review.recommended")
        static let attachments = String(localized: "email.attachments")
        static let attachmentAudio = String(localized: "email.attachment.audio")
        static let attachmentPDF = String(localized: "email.attachment.pdf")
        static let attachmentMarkdown = String(localized: "email.attachment.markdown")
        static let attachmentNone = String(localized: "email.attachment.none")
        static let to = String(localized: "email.to")
        static let mailNotConfigured = String(localized: "email.mail_not_configured")
        static let mailNotConfiguredHint = String(localized: "email.mail_not_configured.hint")
        static let sendTitle = String(localized: "email.send_title")
        static let close = String(localized: "email.close")
        static let shareNote = String(localized: "email.share_note")
        static let button = String(localized: "email.button")
        static let alertTitle = String(localized: "email.alert.title")
        static let openSettings = String(localized: "email.open_settings")

        static func reviewWarning(segmentCount: Int) -> String {
            String(localized: "email.review.warning \(segmentCount)")
        }
    }
}
