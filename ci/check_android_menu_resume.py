"""Check actual rendered menu pixels after Android background/lock cycles."""
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
        light = sum(min(p) > 210 for p in pixels) / len(pixels)
        ink = sum(max(p) < 180 for p in pixels)
        assert light > 0.60, f'{name}: black/covered menu at {label}: {light:.3f}'
        assert ink > 20, f'{name}: blank menu button {label}: {ink} text/icon pixels'
        stats[label] = {'light_fraction': round(light, 4), 'ink_pixels': ink}
    return stats


def open_phone():
    adb('shell', 'am', 'start', '-W', '-n', ACTIVITY)
    time.sleep(1.2)


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
assert 'Reiniciar' in content, 'Account destination did not open after resume'
results.append({'case': 'account-after-resume', 'pixels': check_pixels('menu-account-after-resume', boxes)})
x1, y1, x2, y2 = boxes['Rádio']
adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
time.sleep(1)
results.append({'case': 'radio-after-account', 'pixels': check_pixels('menu-radio-after-account', boxes)})
menu_bounds('menu-final')
(EVIDENCE / 'menu-resume-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
print('PASS: 12 background returns, 3 screen locks, visible menu pixels and working account/radio navigation.')
