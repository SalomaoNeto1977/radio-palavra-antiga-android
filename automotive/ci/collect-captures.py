"""Copy screenshots from the active AAOS driver without cross-shell variables."""
import subprocess

user = subprocess.check_output(["adb", "shell", "am", "get-current-user"], text=True).strip()
if not user.isdigit():
    raise RuntimeError("The emulator did not return a valid active user")
source = f"/storage/emulated/{user}/Android/data/org.palavraantiga.radio.automotive.debug/files/qa"
subprocess.run(["adb", "pull", source, "car-verification/screenshots"], check=True)
