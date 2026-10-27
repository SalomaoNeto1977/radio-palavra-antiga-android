"""Copy screenshots from the active AAOS driver without cross-shell variables."""
import subprocess

bridge = ["adb", "-s", "emulator-5554"]
# AAOS driver files are isolated from the shell user. Only elevate adbd on this
# disposable emulator; never apply this operation to a connected physical car.
emulated = subprocess.check_output(bridge + ["shell", "getprop", "ro.kernel.qemu"], text=True).strip()
if emulated != "1":
    raise RuntimeError("Screenshot collection requires the disposable CI emulator")
subprocess.run(bridge + ["root"], check=True)
subprocess.run(bridge + ["wait-for-device"], check=True)
user = subprocess.check_output(bridge + ["shell", "am", "get-current-user"], text=True).strip()
if not user.isdigit():
    raise RuntimeError("The emulator did not return a valid active user")
source = f"/storage/emulated/{user}/Android/data/org.palavraantiga.radio.automotive.debug/files/qa"
subprocess.run(bridge + ["pull", source, "car-verification/screenshots"], check=True)
