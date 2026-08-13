# Design contract — included minutes

## Direction

**Existing Paperorg Editorial iOS.** This is a continuation of the current
white, low-decoration AppTheme surface system, not a paywall redesign.

## Tokens and layout

- Use the existing `AppTheme`, `.surfaceCard()`, `AccentButtonStyle`, and
  `SecondaryButtonStyle`; do not introduce new colors or a new font.
- Standard content inset: 20–24 pt; grouped content spacing: 12–24 pt.
- Usage state uses a compact text label and native `ProgressView`, never a
  gamified meter or countdown.
- Sign in with Apple uses Apple’s native authorization button/control.

## States

1. Free, unsigned in: explain 30 included monthly minutes and present Sign in
   with Apple plus the existing BYOK route.
2. Free, signed in: remaining included minutes, a quiet upgrade action, and
   no API-key blocker.
3. Threshold: at 3 completed notes or 20 minutes, present an interruptible
   upgrade sheet; dismissing it preserves Free use until 30 minutes.
4. Exhausted: explain the monthly reset and offer Pro and BYOK; never imply a
   purchased subscription.
5. Feature flag off or backend unavailable: existing BYOK/Pro behavior remains
   intact and the UI gives a calm retry/alternative path.

## Accessibility and localization

All new controls have explicit labels, work at Dynamic Type sizes, and use
localized strings in English, French, and German. Error/loading states must
not rely on color alone.
