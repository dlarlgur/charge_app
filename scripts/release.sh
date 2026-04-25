#!/usr/bin/env bash
# 상용 릴리즈 빌드
#   - pubspec_overrides.yaml 을 잠시 치우고 pubspec.yaml 의 git ref 로 빌드
#   - 난독화 + split-debug-info 적용 (symbols 는 ./symbols/<version>/ 에 저장)
#
# 사용법:
#   scripts/release.sh aab   # Android App Bundle (기본)
#   scripts/release.sh apk   # Android APK (테스트용)
#   scripts/release.sh ios   # iOS IPA
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-aab}"
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')

# ── pubspec_overrides.yaml 일시 비활성화 (git ref 강제) ──
OVERRIDE="pubspec_overrides.yaml"
SAVED=""
if [[ -f "$OVERRIDE" ]]; then
  SAVED="$OVERRIDE.saved-$$"
  mv "$OVERRIDE" "$SAVED"
  echo "▶ $OVERRIDE 를 $SAVED 로 잠시 이동 (git ref 모드)"
fi
restore_override() {
  if [[ -n "$SAVED" && -f "$SAVED" ]]; then
    mv "$SAVED" "$OVERRIDE"
    echo "▶ $OVERRIDE 복원 완료"
  fi
}
trap restore_override EXIT INT TERM

SYMBOLS_DIR="./symbols/$VERSION"
mkdir -p "$SYMBOLS_DIR"

echo "▶ flutter clean"
flutter clean

echo "▶ flutter pub get (git ref 로 SDK 해석)"
flutter pub get

echo "▶ flutter build $TARGET --release --obfuscate"
case "$TARGET" in
  aab)
    flutter build appbundle --release --obfuscate --split-debug-info="$SYMBOLS_DIR"
    echo "✅ AAB: build/app/outputs/bundle/release/app-release.aab"
    ;;
  apk)
    flutter build apk --release --obfuscate --split-debug-info="$SYMBOLS_DIR"
    echo "✅ APK: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  ios)
    flutter build ipa --release --obfuscate --split-debug-info="$SYMBOLS_DIR"
    echo "✅ IPA: build/ios/ipa/"
    ;;
  *)
    echo "❌ 알 수 없는 타깃: $TARGET (aab|apk|ios 중 선택)"
    exit 1
    ;;
esac

echo "▶ symbols 보관 위치: $SYMBOLS_DIR"
echo "   (Play Console / App Store Connect 에 크래시 심볼화용으로 업로드)"
