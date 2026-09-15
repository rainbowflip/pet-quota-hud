#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/Core.swift Sources/Desktop.swift tests/main.swift -o .build/tests -framework AppKit -framework CryptoKit
.build/tests
python3 -m unittest discover -s tests -p 'test_*.py'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s' '{"session_id":"test-session","prompt":"must-not-be-stored"}' | PET_QUOTA_HUD_HOME="$tmp" 'dist/Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD' --hook Stop
python3 - "$tmp" <<'PY'
import json, pathlib, sys
files = list((pathlib.Path(sys.argv[1]) / 'signals').glob('*.json'))
assert len(files) == 1
text = files[0].read_text()
assert 'must-not-be-stored' not in text and 'test-session' not in text
assert json.loads(text)['event'] == 'Stop'
print('Hook privacy / real binary check passed')
PY
