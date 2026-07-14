"""Branded HTML email templates for Paperorg Notes."""

from __future__ import annotations

import base64
import html
import re
from datetime import datetime
from pathlib import Path

PRIMARY = "#14223D"
ACCENT = "#F56A0A"
BACKGROUND = "#F5F7FB"
SURFACE = "#FFFFFF"
BORDER = "#E0E5EC"
TEXT_SECONDARY = "#4D607B"

_LOGO_DATA_URI: str | None = None


def _logo_img_tag() -> str:
    global _LOGO_DATA_URI
    if _LOGO_DATA_URI is None:
        logo_path = Path(__file__).resolve().parent / "assets" / "email_logo.png"
        if logo_path.exists():
            encoded = base64.b64encode(logo_path.read_bytes()).decode("ascii")
            _LOGO_DATA_URI = (
                f'<img src="data:image/png;base64,{encoded}" width="48" height="48" '
                f'alt="Paperorg Notes" style="display:block;border-radius:12px;">'
            )
        else:
            _LOGO_DATA_URI = (
                f'<div style="width:48px;height:48px;border-radius:12px;background:{ACCENT};'
                f'color:#fff;font-weight:700;font-size:18px;line-height:48px;text-align:center;">P</div>'
            )
    return _LOGO_DATA_URI


def _section(title: str, body: str, top_padding: int = 16) -> str:
    escaped = html.escape(body.strip()).replace("\n", "<br>")
    return f"""
        <tr>
          <td style="padding:{top_padding}px 28px 0 28px;">
            <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:{ACCENT};margin-bottom:8px;">{html.escape(title)}</div>
            <div style="font-size:15px;line-height:1.65;color:{PRIMARY};background:{BACKGROUND};border:1px solid {BORDER};border-radius:12px;padding:16px 18px;white-space:normal;">{escaped}</div>
          </td>
        </tr>
    """


def _parse_sections(body: str) -> tuple[str | None, str | None]:
    text = body.strip()
    summary_match = re.search(r"SUMMARY\s*\n(.*?)(?:\n---\n|\nTRANSCRIPT\s*\n|$)", text, re.S | re.I)
    transcript_match = re.search(r"TRANSCRIPT\s*\n(.*)$", text, re.S | re.I)
    if summary_match and transcript_match:
        return summary_match.group(1).strip(), transcript_match.group(1).strip()
    if summary_match:
        return summary_match.group(1).strip(), None
    if transcript_match:
        return None, transcript_match.group(1).strip()
    return text, None


def build_html_email(*, subject: str, body: str) -> str:
    title = html.escape(subject.strip() or "Paperorg Notes")
    summary, transcript = _parse_sections(body)

    if summary and transcript:
        sections = _section("Summary", summary) + _section("Transcript", transcript, top_padding=8)
    elif summary:
        sections = _section("Summary", summary)
    elif transcript:
        sections = _section("Transcript", transcript)
    else:
        sections = _section("Note", body)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
</head>
<body style="margin:0;padding:0;background:{BACKGROUND};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:{PRIMARY};">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:{BACKGROUND};padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:{SURFACE};border:1px solid {BORDER};border-radius:16px;overflow:hidden;box-shadow:0 8px 24px rgba(20,34,61,0.08);">
          <tr>
            <td style="background:{PRIMARY};padding:24px 28px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td width="56" valign="middle">{_logo_img_tag()}</td>
                  <td valign="middle" style="padding-left:14px;">
                    <div style="font-size:20px;line-height:1.2;font-weight:700;color:#FFFFFF;">Paperorg Notes</div>
                    <div style="font-size:13px;line-height:1.4;color:rgba(255,255,255,0.78);margin-top:4px;">Capture · Transcribe · Send</div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 28px 8px 28px;border-left:4px solid {ACCENT};">
              <div style="font-size:24px;line-height:1.3;font-weight:700;color:{PRIMARY};">{title}</div>
              <div style="margin-top:12px;">
                <span style="display:inline-block;margin:8px 8px 0 0;padding:6px 10px;border-radius:999px;background:{BACKGROUND};border:1px solid {BORDER};font-size:12px;color:{TEXT_SECONDARY};">{html.escape(datetime.now().strftime("%d %b %Y, %H:%M"))}</span>
              </div>
            </td>
          </tr>
          {sections}
          <tr>
            <td style="padding:20px 28px 28px 28px;border-top:1px solid {BORDER};background:#FAFBFD;">
              <div style="font-size:12px;line-height:1.5;color:{TEXT_SECONDARY};">
                Sent automatically by <strong style="color:{PRIMARY};">Paperorg Notes</strong>.
                Attachments may include audio, PDF, or markdown exports when enabled.
              </div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""
