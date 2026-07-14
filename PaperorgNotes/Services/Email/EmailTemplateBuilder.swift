import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum EmailContentMode: String, Sendable {
    case summaryOnly
    case fullTranscript
    case both

    init(content: EmailContent) {
        switch content {
        case .summaryOnly: self = .summaryOnly
        case .fullTranscript: self = .fullTranscript
        case .both: self = .both
        }
    }
}

struct EmailNoteContent: Sendable {
    let title: String
    let summary: String
    let transcript: String
    let contentMode: EmailContentMode
    let recordedAt: Date
    let durationSeconds: TimeInterval
    let language: AppLanguage
    let outputType: OutputType

    @MainActor
    static func from(note: Note, settings: SettingsService) -> EmailNoteContent {
        EmailNoteContent(
            title: note.title,
            summary: note.displaySummaryShort,
            transcript: note.displayTranscript,
            contentMode: EmailContentMode(content: settings.emailContent),
            recordedAt: note.createdAt,
            durationSeconds: note.durationSeconds,
            language: note.appLanguage,
            outputType: note.noteOutputType
        )
    }

    var plainText: String {
        switch contentMode {
        case .summaryOnly:
            return summary
        case .fullTranscript:
            return transcript
        case .both:
            return """
            SUMMARY
            \(summary)

            ---

            TRANSCRIPT
            \(transcript)
            """
        }
    }
}

enum EmailTemplateBuilder {
    private static let primary = "#14223D"
    private static let accent = "#F56A0A"
    private static let background = "#F5F7FB"
    private static let surface = "#FFFFFF"
    private static let border = "#E0E5EC"
    private static let textSecondary = "#4D607B"

    static func buildHTML(content: EmailNoteContent) -> String {
        let logoTag = logoImgTag()
        let meta = metaRow(content: content)
        let sections = bodySections(content: content)
        let title = escapeHTML(content.title)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>\(title)</title>
        </head>
        <body style="margin:0;padding:0;background:\(background);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:\(primary);">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:\(background);padding:24px 12px;">
            <tr>
              <td align="center">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:\(surface);border:1px solid \(border);border-radius:16px;overflow:hidden;box-shadow:0 8px 24px rgba(20,34,61,0.08);">
                  <tr>
                    <td style="background:\(primary);padding:24px 28px;">
                      <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                        <tr>
                          <td width="56" valign="middle">\(logoTag)</td>
                          <td valign="middle" style="padding-left:14px;">
                            <div style="font-size:20px;line-height:1.2;font-weight:700;color:#FFFFFF;">Paperorg Notes</div>
                            <div style="font-size:13px;line-height:1.4;color:rgba(255,255,255,0.78);margin-top:4px;">Capture · Transcribe · Send</div>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:28px 28px 8px 28px;border-left:4px solid \(accent);">
                      <div style="font-size:24px;line-height:1.3;font-weight:700;color:\(primary);">\(title)</div>
                      \(meta)
                    </td>
                  </tr>
                  \(sections)
                  <tr>
                    <td style="padding:20px 28px 28px 28px;border-top:1px solid \(border);background:#FAFBFD;">
                      <div style="font-size:12px;line-height:1.5;color:\(textSecondary);">
                        Sent automatically by <strong style="color:\(primary);">Paperorg Notes</strong>.
                        Attachments may include audio, PDF, or markdown exports when enabled.
                      </div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </body>
        </html>
        """
    }

    private static func metaRow(content: EmailNoteContent) -> String {
        let date = formattedDate(content.recordedAt)
        let duration = DurationFormatter.format(content.durationSeconds)
        let chips = [
            date,
            duration,
            content.language.displayName,
            content.outputType.displayName
        ]
        let chipHTML = chips.map { chip in
            "<span style=\"display:inline-block;margin:8px 8px 0 0;padding:6px 10px;border-radius:999px;background:\(background);border:1px solid \(border);font-size:12px;color:\(textSecondary);\">\(escapeHTML(chip))</span>"
        }.joined()
        return "<div style=\"margin-top:12px;\">\(chipHTML)</div>"
    }

    private static func bodySections(content: EmailNoteContent) -> String {
        switch content.contentMode {
        case .summaryOnly:
            return section(title: "Summary", body: content.summary)
        case .fullTranscript:
            return section(title: "Transcript", body: content.transcript)
        case .both:
            return section(title: "Summary", body: content.summary)
                + section(title: "Transcript", body: content.transcript, topPadding: 8)
        }
    }

    private static func section(title: String, body: String, topPadding: Int = 16) -> String {
        let escaped = escapeHTML(body).replacingOccurrences(of: "\n", with: "<br>")
        return """
        <tr>
          <td style="padding:\(topPadding)px 28px 0 28px;">
            <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:\(accent);margin-bottom:8px;">\(escapeHTML(title))</div>
            <div style="font-size:15px;line-height:1.65;color:\(primary);background:\(background);border:1px solid \(border);border-radius:12px;padding:16px 18px;white-space:normal;">\(escaped)</div>
          </td>
        </tr>
        """
    }

    private static func logoImgTag() -> String {
        #if canImport(UIKit)
        if let image = UIImage(named: "LaunchLogo"),
           let data = image.pngData() {
            let encoded = data.base64EncodedString()
            return "<img src=\"data:image/png;base64,\(encoded)\" width=\"48\" height=\"48\" alt=\"Paperorg Notes\" style=\"display:block;border-radius:12px;\">"
        }
        #endif
        return "<div style=\"width:48px;height:48px;border-radius:12px;background:\(accent);color:#fff;font-weight:700;font-size:18px;line-height:48px;text-align:center;\">P</div>"
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
