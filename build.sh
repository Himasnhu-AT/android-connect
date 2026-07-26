#!/usr/bin/env bash
#
# build.sh — build the AndroidConnect macOS and Android apps into ./dist.
#
# Usage:
#   ./build.sh            # build both platforms
#   ./build.sh macos      # macOS only
#   ./build.sh android    # Android only
#
# Environment overrides:
#   MAC_CONFIG=Release|Debug   macOS build configuration        (default: Release)
#   JAVA_HOME=<path>           JDK for Gradle; must be 17–21     (default: Android Studio JBR)
#   ANDROID_HOME=<path>        Android SDK                       (default: ~/Library/Android/sdk)
#
# Outputs (./dist):
#   macos/androidconnect.app                         runnable app bundle
#   macos/androidconnect-macos-<ver>-<sha>.zip       zipped bundle for distribution
#   android/androidconnect-debug-<ver>-<sha>.apk     installable debug APK
#   android/androidconnect-release-unsigned-<ver>-<sha>.apk   R8-minified release APK (unsigned)
#   BUILD_MANIFEST.txt                               sizes + SHA-256 of every artifact
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
TARGET="${1:-all}"

# ── pretty logging ───────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=''; G=''; Y=''; R=''; N=''; fi
log()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '  %s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"

# record ARTIFACT in the manifest and echo a success line. Files get a SHA-256; dirs get size only.
record() {
  local label="$1" path="$2" size csum
  size="$(du -sh "$path" 2>/dev/null | cut -f1)"
  if [ -f "$path" ]; then csum="$(shasum -a 256 "$path" | awk '{print $1}')"; else csum="(directory)"; fi
  printf '%-48s  %6s  %s\n' "${path#"$DIST"/}" "$size" "$csum" >> "$MANIFEST"
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

  record "app bundle" "$DIST/macos/androidconnect.app"
  record "zipped bundle" "$zip"
}

# ── Android ──────────────────────────────────────────────────────────────────
build_android() {
  local ver jmajor glog dbg rel

  # Resolve a usable JDK: explicit JAVA_HOME → Android Studio JBR → /usr/libexec/java_home.
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME:-}/bin/java" ]; then
    for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
             "/Applications/Android Studio Preview.app/Contents/jbr/Contents/Home"; do
      [ -x "$j/bin/java" ] && { export JAVA_HOME="$j"; break; }
    done
  fi
  [ -x "${JAVA_HOME:-}/bin/java" ] || export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
  [ -x "${JAVA_HOME:-}/bin/java" ] || die "No JDK found — set JAVA_HOME to a JDK 17–21 (e.g. Android Studio's JBR)."

  jmajor="$("$JAVA_HOME/bin/java" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1)"
  # Kotlin 2.2.20's compiler cannot parse JDK 24+ version strings (throws IllegalArgumentException).
  if [ "${jmajor:-0}" -ge 24 ]; then
    die "JDK $jmajor is too new for this toolchain (Kotlin 2.2.20). Use JDK 17–21 — set JAVA_HOME to Android Studio's JBR."
  fi

  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  [ -d "$ANDROID_HOME" ] || die "Android SDK not found at $ANDROID_HOME — set ANDROID_HOME."

  ver="$(grep -m1 'versionName' "$ANDROID_DIR/app/build.gradle.kts" | sed -E 's/.*"([^"]+)".*/\1/')"
  ver="${ver:-0.0.0}"
  log "Android · debug + release · v$ver · JDK $jmajor"

  glog="$LOG_DIR/android-build.log"
  if ! ( cd "$ANDROID_DIR" && ./gradlew --console=plain assembleDebug assembleRelease ) > "$glog" 2>&1; then
    tail -30 "$glog" >&2
    die "Android build failed — full log: ${glog#"$ROOT"/}"
  fi

  rm -rf "$DIST/android"; mkdir -p "$DIST/android"
  dbg="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
  rel_signed="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
  rel_unsigned="$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"

  [ -f "$dbg" ] || die "debug APK not produced"
  cp "$dbg" "$DIST/android/androidconnect-debug-$ver-$GIT_SHA.apk"
  record "debug APK (installable)" "$DIST/android/androidconnect-debug-$ver-$GIT_SHA.apk"

  # AGP names the release APK `app-release.apk` when a signingConfig is set, else `-unsigned`.
  if [ -f "$rel_signed" ]; then
    cp "$rel_signed" "$DIST/android/androidconnect-release-$ver-$GIT_SHA.apk"
    record "release APK (R8-minified, signed)" "$DIST/android/androidconnect-release-$ver-$GIT_SHA.apk"
  elif [ -f "$rel_unsigned" ]; then
    cp "$rel_unsigned" "$DIST/android/androidconnect-release-unsigned-$ver-$GIT_SHA.apk"
    record "release APK (R8-minified, UNSIGNED — set android/keystore.properties to sign)" "$DIST/android/androidconnect-release-unsigned-$ver-$GIT_SHA.apk"
  else
    warn "release APK not found — skipped"
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
  printf '%-48s  %6s  %s\n' "ARTIFACT" "SIZE" "SHA-256"
  printf '%.0s-' {1..112}; echo
} > "$MANIFEST"

case "$TARGET" in
  all)     build_macos; build_android ;;
  macos)   build_macos ;;
  android) build_android ;;
  *)       die "unknown target '$TARGET' — use: all | macos | android" ;;
esac

echo
log "Done — artifacts in ./dist"
cat "$MANIFEST"
