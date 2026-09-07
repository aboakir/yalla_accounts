#!/usr/bin/env bash
set -euo pipefail

: "${YALLA_LICENSING_BASE_URL:?YALLA_LICENSING_BASE_URL is required}"
: "${YALLA_LICENSE_TRUSTED_KEY_SHA256:?YALLA_LICENSE_TRUSTED_KEY_SHA256 is required}"

export YALLA_STORE_DISTRIBUTION="${YALLA_STORE_DISTRIBUTION:-true}"
export YALLA_PRIVACY_URL="${YALLA_PRIVACY_URL:-${YALLA_LICENSING_BASE_URL%/}/privacy}"
export YALLA_TERMS_URL="${YALLA_TERMS_URL:-${YALLA_LICENSING_BASE_URL%/}/terms}"
export YALLA_ACCOUNT_DELETION_URL="${YALLA_ACCOUNT_DELETION_URL:-${YALLA_LICENSING_BASE_URL%/}/account-deletion}"

echo "=== YALLA C06 iOS RELEASE CANDIDATE BUILD ==="
echo "Licensing endpoint: ${YALLA_LICENSING_BASE_URL}"
echo "Bundle ID expected: ps.yalla.accounts"
echo "Store distribution: ${YALLA_STORE_DISTRIBUTION}"

flutter config --no-enable-swift-package-manager
flutter clean

# Historical Yalla iPhone workflow removes this legacy plugin from the CI snapshot
# only because it caused the known Xcode failure. This does not modify the source
# repository after the CI job ends.
if grep -qE '^[[:space:]]*speech_to_text:' pubspec.yaml; then
  cp pubspec.yaml /tmp/yalla_pubspec_before_c06.yaml
  python3 - <<'PY'
from pathlib import Path
p = Path("pubspec.yaml")
lines = p.read_text(encoding="utf-8").splitlines()
lines = [line for line in lines if not line.lstrip().startswith("speech_to_text:")]
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
fi

flutter pub get

if [[ -f ci/Podfile ]]; then
  cp ci/Podfile ios/Podfile
else
  echo "ERROR: canonical ci/Podfile not found." >&2
  exit 21
fi

pushd ios >/dev/null
pod install
popd >/dev/null

flutter build ios --release --no-codesign \
  --dart-define="YALLA_LICENSING_BASE_URL=${YALLA_LICENSING_BASE_URL}" \
  --dart-define="YALLA_LICENSE_TRUSTED_KEY_SHA256=${YALLA_LICENSE_TRUSTED_KEY_SHA256}" \
  --dart-define="YALLA_STORE_DISTRIBUTION=${YALLA_STORE_DISTRIBUTION}" \
  --dart-define="YALLA_PRIVACY_URL=${YALLA_PRIVACY_URL}" \
  --dart-define="YALLA_TERMS_URL=${YALLA_TERMS_URL}" \
  --dart-define="YALLA_ACCOUNT_DELETION_URL=${YALLA_ACCOUNT_DELETION_URL}"

rm -rf build/ios/c06_ipa
mkdir -p build/ios/c06_ipa/Payload
cp -R build/ios/iphoneos/Runner.app build/ios/c06_ipa/Payload/
(
  cd build/ios/c06_ipa
  /usr/bin/zip -qry ../Yalla_Accounts_C06_Unsigned_iPhone.ipa Payload
)

echo "C06 IPA: build/ios/Yalla_Accounts_C06_Unsigned_iPhone.ipa"
