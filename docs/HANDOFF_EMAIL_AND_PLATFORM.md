# Handoff: Paperorg Notes — Hands-Free Email & Platform Integration

**Date:** 2026-07-14  
**Repo:** `/Users/germaind/dev/Paperorg Notes` (GitHub: `gdelagardelle/paperorg-notes`)  
**Backend:** `https://notes-api.paperorg.com` (systemd: `paperorg-notes-api.service`, env: `/etc/paperorg-notes-api/env`)  
**Platform:** `https://poplatform.paperorg.com` (separate repo — **not in this workspace**)

---

## 1. User goal (driving / normal users)

Users record voice notes while driving. Flow must be:

**Record → Stop → (transcription runs) → email sends automatically — zero taps, no Mail/Outlook UI, no SMTP setup on the phone.**

Target users include:
- Outlook-only users (no Apple Mail configured)
- Apple Mail users
- Non-technical users who cannot set up app passwords or SMTP

**Rejected approaches:**
- `MFMailComposeViewController` — requires tap Send; only works with Mail app accounts
- Share sheet (Outlook/Gmail) — still requires user interaction
- On-device SMTP with app passwords — too complicated for normal users

**Chosen approach:**
- **Server-side email** via notes-api, ideally delegated to **Paperorg Platform** where SMTP is configured once in admin
- iOS: toggle + recipient list only (default mode)

---

## 2. Current architecture

```
iPhone (Paperorg Notes)
  └─ Settings: "Send email after transcription" + recipients
  └─ RecordView.preparePostRecordingEmail() after transcription
       └─ EmailDeliveryService.send(payload)
            ├─ [default] ProBackendClient.sendEmail() → POST notes-api/v1/email/send
            └─ [advanced] SMTPEmailDeliveryService (on-device SMTP, power users)

notes-api (this repo, backend/)
  └─ POST /v1/email/send (multipart: subject, body, recipients JSON, optional audio/pdf/markdown)
       └─ email_delivery.send_email(user_id=...)
            ├─ 1. Platform relay: POST poplatform/internal/v1/email/send?app_id=notes  ← PREFERRED
            ├─ 2. Platform config: GET poplatform/internal/v1/email/config?app_id=notes → smtplib send
            └─ 3. Local fallback: EMAIL_SMTP_* env vars on notes-api (dev only)

Paperorg Platform (NOT in this repo — must be implemented)
  └─ Admin UI: Apps → Notes → Email (from address, SMTP host/port/user/password)
  └─ Internal API (PLATFORM_INTERNAL_TOKEN):
       GET  /internal/v1/email/status?app_id=notes
       POST /internal/v1/email/send?app_id=notes
       GET  /internal/v1/email/config?app_id=notes  (optional fallback)
```

---

## 3. Git state

**Last pushed commit:** `f21aaab` — "Restore SMTP auto-send for hands-free post-recording email."

**Uncommitted local work (IMPORTANT — not pushed yet):**

| Area | Status |
|------|--------|
| Server email relay (`backend/email_delivery.py`, `main.py` endpoints) | New/modified, uncommitted |
| Platform delegation (`backend/platform_client.py`) | Modified, uncommitted |
| iOS simplified email UX + `EmailDeliveryService` | Modified, uncommitted |
| `docs/PLATFORM_EMAIL_API.md` | New, uncommitted |
| `PaperorgNotes/Models/SMTPProviderPreset.swift` | New, uncommitted |

**TestFlight:** Last archive was **1.0.0 (3)** with commit `f21aaab` (on-device SMTP era). Uncommitted iOS changes are **not** in TestFlight yet.

---

## 4. iOS implementation (uncommitted)

### Default user flow (Settings → Email)
1. Toggle **Send email after transcription**
2. Add recipient email(s)
3. Done — no mail setup on phone

SMTP is hidden under **Advanced: send from my own email** → **Use my own mail server**.

### Key files

| File | Role |
|------|------|
| `PaperorgNotes/Services/Email/EmailDeliveryService.swift` | Routes to backend (default) or on-device SMTP (advanced) |
| `PaperorgNotes/Services/Backend/ProBackendClient.swift` | `sendEmail(_ payload:)` → multipart POST `/v1/email/send` |
| `PaperorgNotes/Views/Record/RecordView.swift` | `preparePostRecordingEmail` calls `emailDeliveryService.send` in background Task |
| `PaperorgNotes/Views/Settings/SettingsView.swift` | Simplified email section; SMTP in DisclosureGroup |
| `PaperorgNotes/Services/Settings/SettingsService.swift` | `useOwnMailServerForEmail` (default false), `canAutomaticallySendEmail` |
| `PaperorgNotes/Services/Email/SMTPEmailDeliveryService.swift` | On-device SMTP (advanced only) |
| `PaperorgNotes/Models/SMTPProviderPreset.swift` | Apple Mail / Outlook / Gmail presets for advanced mode |
| `PaperorgNotes/Views/Components/MailComposeView.swift` | Manual "Send Email" button still uses Mail app or share sheet |

### Settings keys
- `sendEmailAfterTranscription` — main toggle
- `useOwnMailServerForEmail` — default **false** (Paperorg sends)
- `emailRecipients` — who receives auto-emails
- SMTP fields only when advanced mode on

### Email always hits notes-api
Even when `usePlatformAuth=YES`, email goes to `proBackendBaseURL` (notes-api), not Platform directly. Platform is called **server-to-server** from notes-api.

---

## 5. notes-api implementation (uncommitted)

### New/modified files
- `backend/email_delivery.py` — send logic with 3-tier fallback
- `backend/main.py` — `GET /v1/email/status`, `POST /v1/email/send`
- `backend/platform_client.py` — `platform_email_relay_available()`, `resolve_platform_email_config()`, `send_platform_email()`
- `backend/config.py` — `EMAIL_SMTP_*` vars (local fallback)
- `backend/rate_limit.py` — `enforce_user_rate_limit()` (50 emails/day/user default)
- `docs/PLATFORM_EMAIL_API.md` — **Platform contract spec**
- `backend/README.md`, `backend/.env.example` — updated docs

### Endpoints (notes-api)

```
GET  /v1/email/status
     Auth: Bearer (legacy HS256 or Platform RS256)
     → {"available": bool, "source": "platform_relay"|"platform_config"|"local_env"|"none"}

POST /v1/email/send
     Auth: Bearer
     multipart/form-data:
       subject, body, recipients (JSON array string)
       optional files: audio, pdf, markdown
     → {"status": "sent"}
```

### Production env (notes-api)

**Recommended (Platform relay):**
```bash
PLATFORM_API_URL=https://poplatform.paperorg.com
PLATFORM_INTERNAL_TOKEN=<same token used for credentials vault>
```

**Dev fallback (until Platform email is live):**
```bash
EMAIL_SMTP_HOST=...
EMAIL_SMTP_PORT=465
EMAIL_SMTP_USERNAME=...
EMAIL_SMTP_PASSWORD=...
EMAIL_FROM_ADDRESS=notes@paperorg.com
EMAIL_FROM_NAME=Paperorg Notes
```

---

## 6. Platform work required (separate repo)

**Read:** `docs/PLATFORM_EMAIL_API.md` in this repo for full spec.

### Admin UI needed
**Apps → Notes → Email:**
- From name, From address
- SMTP host, port, username, password (encrypted at rest)
- Enabled toggle

### Internal API (auth: `PLATFORM_INTERNAL_TOKEN`)

```
GET  /internal/v1/email/status?app_id=notes
→ {"available": true}

POST /internal/v1/email/send?app_id=notes
     multipart: user_id, subject, body, recipients (JSON)
     files: audio, pdf, markdown (optional)
→ {"status": "sent"}

GET  /internal/v1/email/config?app_id=notes   (optional fallback)
→ {"available": true, "smtp_host", "smtp_port", "smtp_username", "smtp_password", "from_address", "from_name"}
```

Same internal token pattern as existing:
`GET /internal/v1/credentials/resolve?provider=openai&app_id=notes`

### Suggested Platform SMTP
Use Paperorg's own mail (e.g. `notes@paperorg.com` via Microsoft 365 / Outlook SMTP). Configure once in Platform — all Notes users benefit.

---

## 7. Other project context (already shipped)

| Topic | Status |
|-------|--------|
| Recording loss on sleep/lock | Fixed in `dffbf25` — checkpoints, background task, no Face ID during recording |
| Review-before-send dark mode | Fixed in `f0831fa` |
| StoreKit / Pro subscription | Backend configured; App Store product `com.paperorg.notes.pro.monthly` was **Missing Metadata** in App Store Connect (blocks on-device Pro verify) |
| notes-api Apple StoreKit API | Working on VPS with `.p8` key file, `APPLE_USE_SANDBOX=true` for TestFlight |
| Platform auth (Phase C/D) | Code ready; Release still has `PAPERORG_USE_PLATFORM_AUTH=NO` in `project.yml` |

---

## 8. Suggested next steps for Claude

### Priority 1 — Platform email (unblocks normal users)
1. Open **Paperorg Platform repo** (not in this workspace)
2. Implement internal email endpoints per `docs/PLATFORM_EMAIL_API.md`
3. Add admin UI for Notes app email / SMTP settings
4. Configure Paperorg SMTP in admin (from address, credentials)
5. Set `PLATFORM_INTERNAL_TOKEN` on notes-api production if not already set
6. Verify: `GET https://notes-api.paperorg.com/v1/email/status` with auth → `source: "platform_relay"`

### Priority 2 — Commit & ship iOS + backend (this repo)
1. Commit all uncommitted changes (see section 3)
2. Bump `CURRENT_PROJECT_VERSION` in `project.yml` (currently 3 in last archive; uncommitted work needs new build)
3. Run `xcodegen generate` + Release archive
4. Upload TestFlight
5. Test: enable auto-email, add recipient, record short note, confirm email arrives with no user interaction

### Priority 3 — Production notes-api deploy
1. Deploy updated `backend/` to VPS (`/opt/paperorg-notes-api/app`)
2. Restart `paperorg-notes-api.service`
3. Ensure `PLATFORM_API_URL` + `PLATFORM_INTERNAL_TOKEN` in `/etc/paperorg-notes-api/env`
4. Remove `EMAIL_SMTP_*` from notes-api once Platform relay works

### Priority 4 — App Store Connect
- Complete subscription metadata for `com.paperorg.notes.pro.monthly` so Pro verify works on device

---

## 9. Testing checklist

- [ ] Platform admin: save Notes email SMTP settings
- [ ] `GET /internal/v1/email/status?app_id=notes` → available true
- [ ] notes-api `/v1/email/status` → source `platform_relay`
- [ ] Record 30s note with auto-email on + recipient set → email received automatically
- [ ] Test with Outlook-only device (no Mail app) — should work via server send
- [ ] Test with Apple Mail user — same, no phone mail setup
- [ ] Advanced mode: on-device SMTP still works for power users
- [ ] Manual "Send Email" on note detail still opens Mail/share sheet

---

## 10. Key conventions

- **Minimize iOS diff scope** — match existing Swift patterns
- **Don't commit** unless user asks
- **project.yml** is source of truth; run `xcodegen generate` after changes
- **Release backend URL:** `https://notes-api.paperorg.com`
- **Release Platform URL:** `https://poplatform.paperorg.com`
- Email content/attachments controlled by existing settings: summary/transcript/both, audio/PDF/markdown toggles
- `reviewBeforeEmail` applies only to manual send button, **not** auto-send after recording

---

## 11. Open questions

1. **Platform repo location?** User has it separately — path unknown to this session.
2. **Which Paperorg mailbox?** User wants to configure from Platform admin — likely `notes@paperorg.com` or similar.
3. **Pro-gating email?** Currently any authenticated notes-api user can send (rate-limited 50/day). Consider Pro-only if abuse is a concern.
4. **Privacy policy update?** Auto-send sends note content through Paperorg servers — may need disclosure update in `docs/APP_STORE_PRIVACY.md`.

---

## 12. Reference: conversation arc

1. Fixed recording loss, sleep/lock hardening
2. Removed SMTP → Mail app compose (user request)
3. Outlook users blocked → share sheet fallback
4. Driving use case → restored on-device SMTP auto-send (too complex for normal users)
5. Added Apple Mail / Outlook / Gmail presets (still too complex)
6. **Current direction:** Paperorg server email via Platform SMTP — simple for users, configurable centrally

**User's latest ask:** Push email through Paperorg Platform with SMTP configured there, not on notes-api or on phones. notes-api side is wired; **Platform implementation is the blocker.**
