#!/usr/bin/env bash
set -euo pipefail
APK="$1"
export RPA_VERIFY_STARTUP="${2:-diagnose}"
mkdir -p startup-evidence
trap 'cp /tmp/emulator.log startup-evidence/emulator.log 2>/dev/null || true; kill "${LOGCAT_PID:-}" 2>/dev/null || true' EXIT
adb install -r "$APK"
adb logcat -c
adb logcat -v threadtime > startup-evidence/logcat.txt &
LOGCAT_PID=$!
adb shell am force-stop org.palavraantiga.radio
adb shell am start -W -n org.palavraantiga.radio/org.palavraantiga.radio_palavra_antiga.MainActivity
sleep 8
timeout 15 adb exec-out screencap -p > startup-evidence/startup-early.png || true
sleep 32
timeout 15 adb exec-out screencap -p > startup-evidence/startup.png || true
timeout 15 adb shell uiautomator dump /sdcard/startup.xml || true
adb pull /sdcard/startup.xml startup-evidence/startup.xml || true
adb shell dumpsys activity activities > startup-evidence/activity.txt || true
kill "$LOGCAT_PID" 2>/dev/null || true
cp /tmp/emulator.log startup-evidence/emulator.log 2>/dev/null || true
python3 - <<'PY'
from pathlib import Path
import re
import os
log = Path('startup-evidence/logcat.txt').read_text(errors='replace')
important = [line for line in log.splitlines() if re.search(r'flutter|AndroidRuntime|AudioService|MissingPlugin|Exception|FATAL', line, re.I)]
print('\n'.join(important[-150:]))
ui = Path('startup-evidence/startup.xml')
print(ui.read_text() if ui.exists() else 'No accessibility snapshot')
if os.environ['RPA_VERIFY_STARTUP'] == 'verify':
    content = ui.read_text() if ui.exists() else ''
    assert 'Música' in content and 'Conta' in content, 'Phone navigation did not appear after release startup'
    assert not any('Unhandled Exception' in line for line in important), 'Unhandled startup exception'
    print('Release startup: phone navigation present, no unhandled exceptions.')
PY
