#!/usr/bin/env bash
#
# build.sh — build the AndroidConnect apps into ./dist.
#
# Default: a SIGNED release APK + the macOS app, with signatures verified.
#
# Usage:
#   ./build.sh            # both: signed APK + macOS app
#   ./build.sh macos      # macOS app only
#   ./build.sh android    # signed APK only
#
# Environment overrides:
#   WITH_DEBUG=1               also build the debug APK (for in-place dev installs)
#   MAC_CONFIG=Release|Debug   macOS build configuration        (default: Release)
#   JAVA_HOME=<path>           JDK for Gradle; must be 17–21     (default: Android Studio JBR)
#   ANDROID_HOME=<path>        Android SDK                       (default: ~/Library/Android/sdk)
#
# The APK is signed with the key in android/keystore.properties (gitignored). If that file is
# missing the release APK is unsigned and this script fails — see android/keystore.properties.
#
set -euo pipefail

# ── locations (script lives at repo root) ────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$ROOT/macos"
ANDROID_DIR="$ROOT/android"
DIST="$ROOT/dist"
BUILD_TMP="$ROOT/.build"
LOG_DIR="$BUILD_TMP/logs"
MANIFEST="$DIST/BUILD_MANIFEST.txt"

MAC_CONFIG="${MAC_CONFIG:-Release}"
WITH_DEBUG="${WITH_DEBUG:-0}"
TARGET="${1:-all}"

# ── pretty logging ───────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=''; G=''; Y=''; R=''; N=''; fi
log()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '  %s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"

record() {
  local label="$1" path="$2" size csum
  size="$(du -sh "$path" 2>/dev/null | cut -f1)"
  if [ -f "$path" ]; then csum="$(shasum -a 256 "$path" | awk '{print $1}')"; else csum="(directory)"; fi
  printf '%-46s  %6s  %s\n' "${path#"$DIST"/}" "$size" "$csum" >> "$MANIFEST"
  ok "$label → dist/${path#"$DIST"/}  ($size)"
}

# ── macOS ────────────────────────────────────────────────────────────────────
build_macos() {
  command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — install Xcode."
  local ver dd app zip xclog
  ver="$(grep -m1 'MARKETING_VERSION' "$MACOS_DIR/androidconnect.xcodeproj/project.pbxproj" \
        | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ")')"
  ver="${ver:-0.0}"
  log "macOS · $MAC_CONFIG · v$ver"

  dd="$BUILD_TMP/macos-derived"
  xclog="$LOG_DIR/macos-build.log"
  rm -rf "$dd"
  if ! xcodebuild \
        -project "$MACOS_DIR/androidconnect.xcodeproj" \
        -scheme androidconnect \
        -configuration "$MAC_CONFIG" \
        -derivedDataPath "$dd" \
        -destination 'generic/platform=macOS' \
        build > "$xclog" 2>&1; then
    tail -30 "$xclog" >&2
    die "macOS build failed — full log: ${xclog#"$ROOT"/}"
  fi

  app="$dd/Build/Products/$MAC_CONFIG/androidconnect.app"
  [ -d "$app" ] || die "built .app not found at $app"

  rm -rf "$DIST/macos"; mkdir -p "$DIST/macos"
  ditto "$app" "$DIST/macos/androidconnect.app"
  zip="$DIST/macos/androidconnect-macos-$ver-$GIT_SHA.zip"
  ditto -c -k --keepParent "$app" "$zip"

  # Verify the code signature so the output states plainly that the app is signed.
  if codesign --verify --deep --strict "$DIST/macos/androidconnect.app" 2>/dev/null; then
    local team
    team="$(codesign -dv "$DIST/macos/androidconnect.app" 2>&1 | sed -nE 's/.*TeamIdentifier=([^ ]+).*/\1/p')"
    ok "app is code-signed${team:+ (team $team)}"
  else
    warn "app is NOT code-signed (check Xcode signing settings)"
  fi

  record "macOS app" "$DIST/macos/androidconnect.app"
  record "macOS app (zip)" "$zip"
}

# ── Android ──────────────────────────────────────────────────────────────────
build_android() {
  local ver jmajor glog rel_signed rel_unsigned out bt apksigner tasks

  # Resolve a usable JDK: explicit JAVA_HOME → Android Studio JBR → /usr/libexec/java_home.
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME:-}/bin/java" ]; then
    for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
             "/Applications/Android Studio Preview.app/Contents/jbr/Contents/Home"; do
      [ -x "$j/bin/java" ] && { export JAVA_HOME="$j"; break; }
    done
  fi
  [ -x "${JAVA_HOME:-}/bin/java" ] || export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
  [ -x "${JAVA_HOME:-}/bin/java" ] || die "No JDK found — set JAVA_HOME to a JDK 17–21 (e.g. Android Studio's JBR)."
  export PATH="$JAVA_HOME/bin:$PATH"

  jmajor="$("$JAVA_HOME/bin/java" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1)"
  # Kotlin 2.2.20's compiler cannot parse JDK 24+ version strings (throws IllegalArgumentException).
  if [ "${jmajor:-0}" -ge 24 ]; then
    die "JDK $jmajor is too new for this toolchain (Kotlin 2.2.20). Use JDK 17–21 — set JAVA_HOME to Android Studio's JBR."
  fi

  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  [ -d "$ANDROID_HOME" ] || die "Android SDK not found at $ANDROID_HOME — set ANDROID_HOME."

  ver="$(grep -m1 'versionName' "$ANDROID_DIR/app/build.gradle.kts" | sed -E 's/.*"([^"]+)".*/\1/')"
  ver="${ver:-0.0.0}"

  tasks="assembleRelease"
  local dbgnote=""
  [ "$WITH_DEBUG" = "1" ] && { tasks="assembleDebug assembleRelease"; dbgnote=" + debug"; }
  log "Android · signed release$dbgnote · v$ver · JDK $jmajor"

  glog="$LOG_DIR/android-build.log"
  # shellcheck disable=SC2086
  if ! ( cd "$ANDROID_DIR" && ./gradlew --console=plain $tasks ) > "$glog" 2>&1; then
    tail -30 "$glog" >&2
    die "Android build failed — full log: ${glog#"$ROOT"/}"
  fi

  rm -rf "$DIST/android"; mkdir -p "$DIST/android"
  rel_signed="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
  rel_unsigned="$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"

  # AGP writes `app-release.apk` when a signingConfig is present, else `app-release-unsigned.apk`.
  if [ ! -f "$rel_signed" ]; then
    [ -f "$rel_unsigned" ] && die "release APK is UNSIGNED — add android/keystore.properties to sign it."
    die "release APK not produced"
  fi

  out="$DIST/android/androidconnect-$ver-$GIT_SHA.apk"
  cp "$rel_signed" "$out"

  # Verify the APK signature so the output states plainly that it's signed.
  bt="$(ls "$ANDROID_HOME/build-tools/" 2>/dev/null | sort -V | tail -1)"
  apksigner="$ANDROID_HOME/build-tools/$bt/apksigner"
  if [ -x "$apksigner" ]; then
    if "$apksigner" verify "$out" >/dev/null 2>&1; then
      local signer
      signer="$("$apksigner" verify --print-certs "$out" 2>/dev/null | sed -nE 's/.*certificate DN: (.*)/\1/p' | head -1)"
      ok "APK signature verified${signer:+ ($signer)}"
    else
      die "APK signature did NOT verify — check android/keystore.properties."
    fi
  else
    warn "apksigner not found — skipped signature verification"
  fi

  record "signed APK" "$out"

  if [ "$WITH_DEBUG" = "1" ] && [ -f "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" ]; then
    cp "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" "$DIST/android/androidconnect-debug-$ver-$GIT_SHA.apk"
    record "debug APK (dev installs)" "$DIST/android/androidconnect-debug-$ver-$GIT_SHA.apk"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────
mkdir -p "$DIST" "$LOG_DIR"
{
  echo "AndroidConnect — build manifest"
  echo "generated : $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "commit    : $GIT_SHA"
  echo "host      : macOS $(sw_vers -productVersion 2>/dev/null || echo '?')"
  echo
  printf '%-46s  %6s  %s\n' "ARTIFACT" "SIZE" "SHA-256"
  printf '%.0s-' {1..110}; echo
} > "$MANIFEST"

case "$TARGET" in
  all)     build_macos; build_android ;;
  macos)   build_macos ;;
  android) build_android ;;
  *)       die "unknown target '$TARGET' — use: all | macos | android" ;;
esac

echo
log "Done — signed artifacts in ./dist"
cat "$MANIFEST"
