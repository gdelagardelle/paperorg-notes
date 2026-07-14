# Paperorg Platform — Email API for Notes

notes-api delegates hands-free note email to the **Paperorg Platform** when `PLATFORM_API_URL` and `PLATFORM_INTERNAL_TOKEN` are set on the server. SMTP credentials and the **From** address are configured once in the Platform admin — not on each phone and not in notes-api env.

## Priority order (notes-api)

1. **Platform relay** — `POST /internal/v1/email/send` (recommended)
2. **Platform config** — `GET /internal/v1/email/config` (notes-api sends via SMTP using returned settings)
3. **Local fallback** — `EMAIL_SMTP_*` env vars on notes-api (dev only)

## Authentication

All endpoints use the existing internal service token:

```
Authorization: Bearer {PLATFORM_INTERNAL_TOKEN}
```

Same token as `/internal/v1/credentials/resolve`.

## Endpoints to implement on Platform

### 1. Status (relay mode)

```
GET /internal/v1/email/status?app_id=notes
→ 200 {"available": true}
```

`available: true` when SMTP is configured for the `notes` app in Platform admin.

### 2. Send (relay mode — recommended)

```
POST /internal/v1/email/send?app_id=notes
Content-Type: multipart/form-data

Fields:
  user_id     — notes user id (Platform sub or legacy device id)
  subject     — email subject
  body        — plain text fallback body
  html_body   — branded HTML body (preferred for display)
  recipients  — JSON array string, e.g. ["user@example.com"]

Files (optional):
  audio       — audio/m4a
  pdf         — application/pdf
  markdown    — text/markdown

→ 200 {"status": "sent"}
→ 4xx {"detail": "..."}
```

Platform sends using SMTP configured for `app_id=notes`. Rate-limit per user/day on Platform side.

### 3. Config (optional fallback)

If relay is not implemented yet, expose SMTP settings for notes-api to send directly:

```
GET /internal/v1/email/config?app_id=notes
→ 200 {
  "available": true,
  "smtp_host": "smtp.example.com",
  "smtp_port": 465,
  "smtp_username": "notes@paperorg.com",
  "smtp_password": "...",
  "from_address": "notes@paperorg.com",
  "from_name": "Paperorg Notes"
}
```

## Platform admin UI (suggested)

Under **Apps → Notes → Email**:

| Field | Example |
|-------|---------|
| From name | Paperorg Notes |
| From address | notes@paperorg.com |
| SMTP host | smtp-mail.outlook.com |
| SMTP port | 465 |
| SMTP username | notes@paperorg.com |
| SMTP password | (app password, stored encrypted) |
| Enabled | ✓ |

Save once — all Notes users get hands-free auto-send without configuring mail on their phone.

## notes-api production env

```bash
PLATFORM_API_URL=https://poplatform.paperorg.com
PLATFORM_INTERNAL_TOKEN=...
```

Remove `EMAIL_SMTP_*` from notes-api once Platform relay is live.

## iOS app

No changes required. The app calls `POST https://notes-api.paperorg.com/v1/email/send`; notes-api forwards to Platform when configured.
