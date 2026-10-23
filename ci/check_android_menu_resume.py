"""Check menu/Conta pixels after background and Activity recreation with audio."""
import io
import json
import re
import subprocess
import time
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image


EVIDENCE = Path('startup-evidence')
EVIDENCE.mkdir(exist_ok=True)
ACTIVITY = 'org.palavraantiga.radio/org.palavraantiga.radio_palavra_antiga.MainActivity'
LABELS = ['Rádio', 'Música', 'Conta', 'WhatsApp']


def adb(*args):
    return subprocess.run(['adb', *args], check=True, capture_output=True, timeout=25).stdout


def menu_bounds(name):
    adb('shell', 'uiautomator', 'dump', '/sdcard/menu.xml')
    xml = adb('shell', 'cat', '/sdcard/menu.xml')
    (EVIDENCE / f'{name}.xml').write_bytes(xml)
    tree = ElementTree.fromstring(xml)
    boxes = {}
    for node in tree.iter('node'):
        text = node.get('text', '') + '\n' + node.get('content-desc', '')
        numbers = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
        if len(numbers) != 4:
            continue
        for label in LABELS:
            if label in text.splitlines():
                boxes[label] = numbers
    assert set(boxes) == set(LABELS), f'Menu accessibility missing: {boxes}'
    return boxes


def check_pixels(name, boxes):
    image = Image.open(io.BytesIO(adb('exec-out', 'screencap', '-p'))).convert('RGB')
    image.save(EVIDENCE / f'{name}.png')
    stats = {}
    for label, box in boxes.items():
        pixels = list(image.crop(box).getdata())
        light = sum(sum(p) > 555 for p in pixels) / len(pixels)
        ink = sum(max(p) < 180 for p in pixels)
        assert light > 0.60, f'{name}: black/covered menu at {label}: {light:.3f}'
        assert ink > 20, f'{name}: blank menu button {label}: {ink} text/icon pixels'
        stats[label] = {'light_fraction': round(light, 4), 'ink_pixels': ink}
    return stats


def open_phone():
    # Launcher intent also used by the Play Store's Open action.
    adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
        '-c', 'android.intent.category.LAUNCHER', '-f', '0x10200000', '-n', ACTIVITY)
    time.sleep(1.2)


def playing_audio(name):
    state = adb('shell', 'dumpsys', 'media_session').decode(errors='replace')
    (EVIDENCE / f'{name}-media-session.txt').write_text(state)
    return 'org.palavraantiga.radio' in state and re.search(r'state=(?:3\b|PLAYING)', state) is not None


def tap_menu(label, boxes):
    x1, y1, x2, y2 = boxes[label]
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    time.sleep(1)


def check_account(name, boxes):
    tap_menu('Conta', boxes)
    menu_bounds(name)
    content = (EVIDENCE / f'{name}.xml').read_text()
    assert 'A tua conta' in content, 'Account destination did not open'
    pixels = check_pixels(name, boxes)
    image = Image.open(EVIDENCE / f'{name}.png').convert('RGB')
    # Accessibility can remain present even when the entire Flutter surface is
    # black. Check actual account-body pixels, not only its text semantics.
    top = image.height // 12
    bottom = min(box[1] for box in boxes.values())
    body = list(image.crop((0, top, image.width, bottom)).getdata())
    assert sum(sum(p) > 555 for p in body) / len(body) > 0.4, 'Account surface is black'
    return pixels


adb('shell', 'pm', 'grant', 'org.palavraantiga.radio', 'android.permission.POST_NOTIFICATIONS')
open_phone()
boxes = menu_bounds('menu-before')
results = [{'case': 'before', 'pixels': check_pixels('menu-before', boxes)}]
for cycle in range(1, 13):
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(0.3)
    open_phone()
    name = f'menu-resume-{cycle:02d}'
    results.append({'case': name, 'pixels': check_pixels(name, boxes)})

for cycle in range(1, 4):
    adb('shell', 'input', 'keyevent', 'KEYCODE_SLEEP')
    time.sleep(0.4)
    adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    adb('shell', 'wm', 'dismiss-keyguard')
    open_phone()
    name = f'menu-unlock-{cycle:02d}'
    results.append({'case': name, 'pixels': check_pixels(name, boxes)})

# Verify a menu button actually navigates after the last resume.
x1, y1, x2, y2 = boxes['Conta']
adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
time.sleep(1)
menu_bounds('menu-account-after-resume')
content = (EVIDENCE / 'menu-account-after-resume.xml').read_text()
assert 'A tua conta' in content, 'Account destination did not open after resume'
results.append({'case': 'account-after-resume', 'pixels': check_pixels('menu-account-after-resume', boxes)})
x1, y1, x2, y2 = boxes['Rádio']
adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
time.sleep(1)
results.append({'case': 'radio-after-account', 'pixels': check_pixels('menu-radio-after-account', boxes)})

# Reproduce closing the phone window while the notification player stays alive.
# force-stop is deliberately excluded: it would also kill the audio engine and
# miss the retained-engine/reattached-surface failure reported on the phone.
if not playing_audio('before-audio-start'):
    menu_bounds('audio-start-controls')
    tree = ElementTree.fromstring((EVIDENCE / 'audio-start-controls.xml').read_bytes())
    for node in tree.iter('node'):
        label = node.get('text', '') + ' ' + node.get('content-desc', '')
        if 'Tocar rádio' in label:
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds', '')))
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            break
    else:
        # An already registered media session can also accept a headset Play.
        adb('shell', 'cmd', 'media_session', 'dispatch', 'play')
for attempt in range(20):
    if playing_audio('audio-start'):
        break
    time.sleep(1)
else:
    raise AssertionError('Radio must be playing before testing Activity recreation')

pid = adb('shell', 'pidof', 'org.palavraantiga.radio').strip()
assert pid, 'Audio process is missing'
for cycle in range(1, 4):
    adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    time.sleep(1)
    activities = adb('shell', 'dumpsys', 'activity', 'activities').decode(errors='replace')
    (EVIDENCE / f'closed-{cycle}-activities.txt').write_text(activities)
    resumed = [line for line in activities.splitlines() if 'mResumedActivity' in line or 'topResumedActivity' in line]
    assert not any('org.palavraantiga.radio/' in line for line in resumed), 'Phone Activity did not close'
    assert adb('shell', 'pidof', 'org.palavraantiga.radio').strip() == pid, 'Closing phone UI restarted audio process'
    assert playing_audio(f'closed-{cycle}'), 'Audio stopped when phone window closed'
    open_phone()
    name = f'menu-reattach-{cycle:02d}'
    boxes = menu_bounds(name)
    results.append({'case': name, 'pixels': check_pixels(name, boxes)})
    assert adb('shell', 'pidof', 'org.palavraantiga.radio').strip() == pid, 'Reopening restarted audio process'
    assert playing_audio(f'reopened-{cycle}'), 'Audio stopped on reopen'
    results.append({'case': f'account-reattach-{cycle}', 'pixels': check_account(f'account-reattach-{cycle}', boxes)})
    tap_menu('Rádio', boxes)

menu_bounds('menu-final')
(EVIDENCE / 'menu-resume-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
print('PASS: 12 background returns, 3 screen locks, 3 closed-Activity reopens with audio, visible menu and account pixels.')
