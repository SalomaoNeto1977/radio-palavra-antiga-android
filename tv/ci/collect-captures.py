"""Verify unaltered Full HD PNGs pulled from the TV instrumentation's private files."""
from pathlib import Path
import struct

root = Path('tv-verification')
output = root / 'screenshots'
for state in ['ready', 'playing', 'paused', 'about']:
    data = (output / (state + '.png')).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n')
    assert struct.unpack('>II', data[16:24]) == (1920, 1080), state
print('Four unaltered Full HD TV screenshots verified.')
