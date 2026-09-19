#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "$(uname -s)" == "Darwin" ]] || { echo 'iPhone builds require a macOS/Xcode runner.'; exit 1; }
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub --concurrency=4 --timeout=60s
cp ci/Podfile ios/Podfile
(cd ios && pod install --repo-update)
flutter build ios --release --no-pub --no-codesign \
  --dart-define=YALLA_OWNER_LOCAL_FULL_ACCESS=true
APP="build/ios/iphoneos/Runner.app"
[[ -d "$APP" ]]
for key in UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist")" == 'true' ]]
done
OUT="build/ios/unified_owner_ipa/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/Runner.app"
(cd "$OUT" && zip -qry Yallah_Accounts_Unified_Owner_iPhone.ipa Payload)
shasum -a 256 "$OUT/Yallah_Accounts_Unified_Owner_iPhone.ipa" > "$OUT/SHA256.txt"
echo "Unsigned owner-only IPA: $OUT/Yallah_Accounts_Unified_Owner_iPhone.ipa"
