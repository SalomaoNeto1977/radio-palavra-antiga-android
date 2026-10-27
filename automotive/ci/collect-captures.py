"""Extract PNG attachments emitted by the instrumentation reporting channel."""
from pathlib import Path
import base64
import re
import struct

root = Path("car-verification")
output = root / "screenshots"
output.mkdir(exist_ok=True)
found = set()
for report in root.glob("instrumentation-*.txt"):
    for line in report.read_text().splitlines():
        match = re.fullmatch(
            r"AAOS_SCREENSHOT ((?:landscape|portrait)-(?:playing|paused)\.png) ([A-Za-z0-9+/=]+)",
            line.strip(),
        )
        if match:
            data = base64.b64decode(match.group(2), validate=True)
            if not data.startswith(b"\x89PNG\r\n\x1a\n"):
                raise RuntimeError("Invalid screenshot attachment")
            dimensions = struct.unpack(">II", data[16:24])
            required = (800, 1280) if match.group(1).startswith("portrait-") else (1024, 768)
            if dimensions != required:
                raise RuntimeError(
                    f"Incorrect dimensions for {match.group(1)}: {dimensions}, expected {required}"
                )
            (output / match.group(1)).write_bytes(data)
            found.add(match.group(1))
expected = {f"{layout}-{state}.png" for layout in ["landscape", "portrait"]
            for state in ["playing", "paused"]}
if found != expected:
    raise RuntimeError(f"Missing screenshot attachments: {sorted(expected - found)}")
print("Collected four native AAOS screenshots at the required Google Play dimensions.")
