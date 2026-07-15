# AndroidConnect

A local-first link between a **Mac** and an **Android** phone — discover, pair, and share
effortlessly over your Wi-Fi. No cloud, no account, end-to-end encrypted. Built to the
Freeholt/Synthai manifesto: native, private, calm.

> Think KDE Connect / Phone Link, but LAN-only and native on both ends.

## Layout

```
android-connect/
├── protocol/     # THE CONTRACT — wire protocol both apps implement (start here)
│   ├── PROTOCOL.md
│   └── messages.schema.json
├── macos/        # native SwiftUI menu-bar app (Xcode)
└── android/      # native Kotlin + Jetpack Compose app (Gradle)
```

The two apps share no code. [`protocol/PROTOCOL.md`](protocol/PROTOCOL.md) is the single source of
truth; if you change the wire format, bump `PROTOCOL_VERSION` and update both sides + the schema.

## How it works

- **Discovery:** mDNS/Bonjour (`_androidconnect._tcp`) — zero-config on the same Wi-Fi.
- **Transport:** one persistent TLS 1.3 TCP connection; JSON control frames + raw binary chunks
  for file data, multiplexed on one socket.
- **Trust:** each device holds a persistent self-signed cert (Keychain / Android Keystore). Pairing
  is trust-on-first-use with **cert-fingerprint pinning**, confirmed by scanning a QR on the Mac
  (numeric code fallback). Paired devices reconnect silently.

## Build & run

### macOS (Xcode 26+, macOS 26.3+)
```bash
cd macos
xcodebuild -project androidconnect.xcodeproj -scheme androidconnect -configuration Debug build
# or just open androidconnect.xcodeproj in Xcode and Run.
```
Runs as a **menu-bar agent** (no Dock icon). First mDNS use prompts for local-network access.

### Android (JDK 17+, Android SDK 36)
The build needs a JDK and the Android SDK. If they aren't on your PATH:
```bash
cd android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
./gradlew :app:assembleDebug
# install on a *physical* device (emulator mDNS is unreliable):
adb install app/build/outputs/apk/debug/app-debug.apk
```
`minSdk 26`, `target/compileSdk 36`. `local.properties` points Gradle at your SDK (not committed).

## Permissions (guided in-app during onboarding)
- **Android:** local-network + nearby-devices, a foreground service (persistent link), camera (QR
  pairing), notification access (mirroring), phone/contacts/call-log (call control), media (files).
- **macOS:** local network, incoming/outgoing connections, user-selected files (sandboxed).

## Roadmap
- **M0 ✅** project setup + protocol contract + buildable native shells
- **M1** discovery + secure pairing (the effortless core)
- **M2** clipboard sync · **M3** file/photo transfer · **M4** notification mirroring · **M5** call handling
- **v2** screen mirror + remote control

## Known platform limits (by design, surfaced in the UI)
- Android background clipboard read is blocked (10+) → Android→Mac clipboard pushes when the app is foreground.
- Call **audio** can't route to the Mac over LAN → call feature is caller-ID + answer/decline/end only; audio stays on the phone.
- Notification mirroring needs the one-time Notification-access grant.
