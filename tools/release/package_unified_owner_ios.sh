#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="build/ios/iphoneos/Runner.app"
OUT="build/ios/unified_owner_ipa/${CM_BUILD_ID:-local-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ -d "$APP" ]]
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/Runner.app"
export YALLAH_IPA_OUTPUT="$OUT"
python3 - <<'PY'
import json, os, pathlib, plistlib, subprocess
out = pathlib.Path(os.environ['YALLAH_IPA_OUTPUT'])
app = out / 'Payload' / 'Runner.app'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'ps.yalla.accounts'
assert info['CFBundleShortVersionString'] == '1.0.2'
assert str(info['CFBundleVersion']) == '21'
for key in ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'):
    assert info.get(key) is True, key
record = json.loads(pathlib.Path('build/ios/unified_evidence/SOURCE_PROVENANCE.json').read_text())
record.update(bundleId=info['CFBundleIdentifier'], bundleVersion=str(info['CFBundleVersion']),
              signing='unsigned-owner-personal', physicalDeviceTested=False)
(out / 'BUILD_MANIFEST.json').write_text(json.dumps(record, indent=2) + '\n')
PY
(cd "$OUT" && zip -qry Yallah_Accounts_Owner_1.0.2_21_DB84_iPhone.ipa Payload)
shasum -a 256 "$OUT/Yallah_Accounts_Owner_1.0.2_21_DB84_iPhone.ipa" > "$OUT/SHA256.txt"
