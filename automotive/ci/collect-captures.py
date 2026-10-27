"""Extract PNG attachments emitted by the instrumentation reporting channel."""
from pathlib import Path
import base64
import re

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
            (output / match.group(1)).write_bytes(data)
            found.add(match.group(1))
expected = {f"{layout}-{state}.png" for layout in ["landscape", "portrait"]
            for state in ["playing", "paused"]}
if found != expected:
    raise RuntimeError(f"Missing screenshot attachments: {sorted(expected - found)}")
print("Collected four native AAOS screenshots from the test reports.")
