"""Keep unaltered 1920x1080 PNGs captured by the TV emulator's instrumentation."""
from pathlib import Path
import base64
import re
import struct

root = Path('tv-verification')
output = root / 'screenshots'
output.mkdir(exist_ok=True)
found = set()
for line in (root / 'instrumentation.txt').read_text().splitlines():
    match = re.fullmatch(r'TV_SCREENSHOT (ready|playing|paused|about)\.png ([A-Za-z0-9+/=]+)', line.strip())
    if match:
        data = base64.b64decode(match.group(2), validate=True)
        assert data.startswith(b'\x89PNG\r\n\x1a\n')
        assert struct.unpack('>II', data[16:24]) == (1920, 1080)
        (output / (match.group(1) + '.png')).write_bytes(data)
        found.add(match.group(1))
assert found == {'ready', 'playing', 'paused', 'about'}, found
print('Four unaltered Full HD TV screenshots extracted.')
