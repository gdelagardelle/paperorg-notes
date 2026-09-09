# Google Play listing — Paperorg Notes

Package: `com.paperorg.notes`. Privacy policy: https://gdelagardelle.github.io/paperorg-notes/privacy.html

Paste these into Play Console. Graphics live in `docs/play-listing/`.

## Graphics

| Asset | File | Spec |
|---|---|---|
| High-res icon | `icon-512.png` | 512×512 PNG, 32-bit |
| Feature graphic | `feature-graphic-1024x500.png` | 1024×500 PNG, no alpha |
| Phone screenshot 1 | `phone-01-record.png` | 1080×1920 |
| Phone screenshot 2 | `phone-02-notes.png` | 1080×1920 |
| Phone screenshot 3 | `phone-03-detail.png` | 1080×1920 |
| Phone screenshot 4 | `phone-04-plan.png` | 1080×1920 |

Replace the three UI mockups with device captures from internal testing before production review. The feature graphic can ship as-is.

## English

**Title:** Paperorg Notes  
**Short description (max 80):** Luxembourgish voice notes. Record, transcribe, summarise and share.
**Full description:**

Paperorg Notes turns speech into structured notes. Record on this phone, transcribe in Lëtzebuergesch, French, German, English and Portuguese, and get a summary, action items, and a PDF you can send.

Free includes 30 minutes of cloud transcription each month, in recordings of at most 3 minutes — a voice memo, not a meeting. No account and no API keys.

Paperorg Pro is 10 hours a month and up to 3 hours in one recording, sold through Google Play. Cancel anytime in Play subscriptions.

Lëtzebuergesch uses LuxASR from the University of Luxembourg. Other languages use OpenAI, then ElevenLabs. Audio stays on the device until you transcribe. Export or delete everything from Settings.

**Keywords / tags:** voice notes, transcription, Luxembourgish, Lëtzebuergesch, meeting notes, AI summary, dictation

## French

**Title:** Paperorg Notes  
**Short description (max 80):** Notes vocales en luxembourgeois. Enregistrez, transcrivez et partagez.
**Full description:**

Paperorg Notes transforme la voix en notes structurées. Enregistrez sur ce téléphone, transcrivez en lëtzebuergesch, français, allemand, anglais et portugais, et obtenez un résumé, des actions et un PDF à envoyer.

L’offre gratuite comprend 30 minutes de transcription cloud par mois, en enregistrements de 3 minutes maximum — un mémo vocal, pas une réunion. Sans compte ni clé API.

Paperorg Pro, c’est 10 heures par mois et jusqu’à 3 heures en un enregistrement, vendu via Google Play. Résiliez à tout moment dans les abonnements Play.

Le lëtzebuergesch passe par LuxASR (Université du Luxembourg). Les autres langues utilisent OpenAI, puis ElevenLabs. L’audio reste sur l’appareil jusqu’à la transcription. Exportez ou supprimez tout depuis Réglages.

## German

**Title:** Paperorg Notes  
**Short description (max 80):** Luxemburgische Sprachnotizen aufnehmen, transkribieren und teilen.
**Full description:**

Paperorg Notes macht aus Sprache strukturierte Notizen. Nehmen Sie auf diesem Telefon auf, transkribieren Sie auf Lëtzebuergesch, Französisch, Deutsch, Englisch und Portugiesisch, und erhalten Sie Zusammenfassung, Aufgaben und ein PDF zum Versand.

Free umfasst 30 Minuten Cloud-Transkription im Monat, in Aufnahmen von höchstens 3 Minuten — eine Sprachnotiz, kein Meeting. Ohne Konto und ohne API-Schlüssel.

Paperorg Pro sind 10 Stunden im Monat und bis zu 3 Stunden in einer Aufnahme, über Google Play. Kündigung jederzeit in den Play-Abos.

Lëtzebuergesch nutzt LuxASR der Universität Luxemburg. Andere Sprachen nutzen OpenAI, dann ElevenLabs. Audio bleibt bis zur Transkription auf dem Gerät. Export oder Löschung aller Daten in den Einstellungen.

## Data safety (Play)

| Data type | Collected | Shared | Purpose |
|---|---|---|---|
| Device or other IDs | Yes (app-generated UUID) | With Paperorg backend | App functionality — usage limits |
| Purchase history | Yes (Pro) | With Google Play; verified by Paperorg | App functionality |
| Audio files | Yes, while transcribing | Paperorg, then LuxASR / OpenAI / ElevenLabs | App functionality |
| Other user content (transcripts) | Yes, while summarising | Paperorg and AI processors | App functionality |
| Email address | Optional, user-entered recipients | Paperorg mail sending | App functionality |

Not collected: location, contacts, photos, browsing, advertising IDs, health.

**Encrypted in transit:** yes (HTTPS).  
**Users can request deletion:** yes (Delete all data in Settings; email the controller named in the privacy policy).  
**Data is not sold.**  
**No advertising / no tracking.**

Microphone: recording only. Notifications: shown while a recording is in progress.

## Content rating

Questionnaire: tools / productivity, user-generated audio that the user records, no violence, no sharing to a public feed.

## Subscription (Play)

Product ID `pro` (immutable). Base plans:

| Base plan | Period | Price |
|---|---|---|
| `monthly` | 1 month | €5.99 |
| `annual` | 1 year | €49.99 |

See `PLAY_BILLING_SETUP.md` for license testers, Publisher access, and RTDN.
