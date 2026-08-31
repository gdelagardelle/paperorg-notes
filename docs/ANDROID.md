# Android (v1)

Native Kotlin / Jetpack Compose client for Paperorg Notes. Same API as iOS:
`https://notes-api.paperorg.com`.

## Open in Android Studio

1. **File → Open** → `android/` in this repo (not the iOS project).
2. Wait for Gradle sync. JDK 17 (`/opt/homebrew/opt/openjdk@17`).
3. Pick a phone or emulator, Run.

Command line:

```bash
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

The debug APK is `android/app/build/outputs/apk/debug/app-debug.apk`.

## Point at a local API

Create `android/local.properties` (gitignored):

```
sdk.dir=/Users/YOU/Library/Android/sdk
notesApiUrl=http://10.0.2.2:8080
```

`10.0.2.2` is the emulator's host loopback. A USB phone needs the Mac's LAN
address, and the notes-api must be running with `PAPERORG_DEV_MODE=true`.

## Play Integrity

Free minutes on Android use Google Play Integrity, the counterpart of iOS
App Attest. The production API must have:

```
PLAY_INTEGRITY_ENABLED=true
PLAY_INTEGRITY_PACKAGE_NAME=com.paperorg.notes
PLAY_INTEGRITY_SERVICE_ACCOUNT_FILE=/path/to/google-service-account.json
```

The service account needs the Play Integrity API User role. Put the JSON on
the server through PoVault; never commit it.

Until that flag is on production, Android Free transcription 403s. A USB debug
build also needs the Google Cloud **project number** (not a secret) in
`android/local.properties`:

```
playCloudProjectNumber=123456789012
```

Google will not issue a token for an app that is not yet on Play unless this
number is set. The API only requires `MEETS_DEVICE_INTEGRITY`, so a real
Samsung with Play services can pass before the listing exists. It does not
require `PLAY_RECOGNIZED` until the app is on the store.

Pro is sold through Google Play Billing; see `PLAY_BILLING_SETUP.md` for the
Play Console side, which has to exist before a purchase can be tested.

## What v1 includes

Record (pause/resume, keeps recording with the screen locked), transcribe +
summarize through notes-api, library, search, PDF export, GDPR export zip,
delete all, portrait lock, privacy consent. UI strings in English, French,
and German.
