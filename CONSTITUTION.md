# Constitution

1. Match the existing SwiftUI/SwiftData/FastAPI architecture; no unrelated
   refactors.
2. Verify Apple identity tokens server-side against Apple’s issuer, audience,
   signature, and expiration. Never trust a client-sent Apple subject.
3. Free included entitlement requires verified Apple identity and a backend
   flag. Device-only legacy tokens never receive free provider credit.
4. The backend owns quota enforcement and audio duration metering; no client
   duration field may determine billed usage.
5. Keep the new feature disabled by default and preserve legacy Pro/BYOK paths
   while disabled.
6. New user-visible copy must use the string catalog with English, French, and
   German localizations; no hard-coded new UI strings.
7. Follow existing iOS style: system typography, AppTheme surfaces, native
   buttons/sheets, 44pt targets, Dynamic Type, and motion no longer than 0.2s.
8. Do not change App Store Connect, deploy, push, or modify the original
   checkout in this round.
