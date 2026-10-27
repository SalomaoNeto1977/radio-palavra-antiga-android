"""Set generic AAOS landscape dimensions without an Android Studio-only profile."""
from pathlib import Path
import os

android_user = Path(os.environ.get("ANDROID_USER_HOME", str(Path.home() / ".android")))
avd_home = Path(os.environ.get("ANDROID_AVD_HOME", str(android_user / "avd")))
path = avd_home / "test.avd" / "config.ini"
lines = path.read_text().splitlines()
values = {
    "hw.lcd.width": "1408",
    "hw.lcd.height": "792",
    "hw.lcd.density": "160",
    "hw.mainKeys": "no",
    "hw.keyboard": "yes",
}
lines = [line for line in lines if line.split("=", 1)[0].strip() not in values]
lines.extend(f"{key}={value}" for key, value in values.items())
path.write_text("\n".join(lines) + "\n")
print("Configured generic AAOS display: 1408 x 792")
