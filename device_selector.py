"""Safe auto-selection of Android devices exposed through multiple ADB transports.

Aliases are deduplicated ONLY if they share the same kernel boot UUID.
When devices differ, choose a unique device running Google One or the only
one with Google One installed. Never choose arbitrarily among candidates.
"""
import re
import subprocess

GOOGLE_ONE = "com.google.android.apps.subscriptions.red"
BOOT_UUID = re.compile(r"^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$")


def adb_command(adb, *args):
    try:
        return subprocess.run([str(adb), *args], capture_output=True,
                              text=True, errors="replace", timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return None


def online_serials(adb):
    result = adb_command(adb, "devices")
    if result is None or result.returncode != 0:
        return []
    online = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2 and fields[1] == "device":
            online.append(fields[0])
    return online


def usb_serials(adb):
    """Return online ADB serials connected directly over USB."""
    result = adb_command(adb, "devices", "-l")
    if result is None or result.returncode != 0:
        return set()
    usb = set()
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2 and fields[1] == "device" and any(
            token.startswith("usb:") for token in fields[2:]
        ):
            usb.add(fields[0])
    return usb


def boot_uuid(adb, serial):
    result = adb_command(adb, "-s", serial, "shell", "cat", "/proc/sys/kernel/random/boot_id")
    if result is None or result.returncode != 0:
        return ""
    value = result.stdout.strip()
    return value.lower() if BOOT_UUID.fullmatch(value) else ""


def running_google_one(adb, serial):
    result = adb_command(adb, "-s", serial, "shell", "pidof", GOOGLE_ONE)
    return bool(result is not None and result.returncode == 0 and
                any(token.isdigit() for token in result.stdout.split()))


def installed_google_one(adb, serial):
    result = adb_command(adb, "-s", serial, "shell", "pm", "path", GOOGLE_ONE)
    return bool(result is not None and result.returncode == 0 and
                "package:" in result.stdout)


def prefer_alias(serials, *, usb=None):
    # When prefer_usb supplies known USB transports for a single device's
    # aliases (e.g. USB serial + ADB over TCP/Wi-Fi), prefer the direct USB
    # transport so Frida USB matching uses the exact serial.
    usb_set = usb or set()
    return sorted(serials, key=lambda s: (
        0 if s in usb_set else 1,
        0 if re.fullmatch(r"emulator-\d+", s) else 1,
        s,
    ))[0]


def auto_select_device(adb, *, preferred=None, serials=None, prefer_usb=False):
    """Return a single serial, or None if there is no safe unique choice."""
    online = list(dict.fromkeys(serials if serials is not None else online_serials(adb)))
    if preferred:
        return preferred if preferred in online else None
    if not online:
        return None
    if len(online) == 1:
        return online[0]

    usb = usb_serials(adb) if prefer_usb else set()
    groups = {}
    for serial in online:
        boot = boot_uuid(adb, serial)
        key = "boot:" + boot if boot else "transport:" + serial
        groups.setdefault(key, []).append(serial)
    representatives = [prefer_alias(group, usb=usb) for group in groups.values()]
    if len(representatives) == 1:
        return representatives[0]

    if prefer_usb:
        usb_candidates = [s for s in representatives if s in usb]
        if len(usb_candidates) == 1:
            return usb_candidates[0]

    for test in (running_google_one, installed_google_one):
        candidates = [s for s in representatives if test(adb, s)]
        if len(candidates) == 1:
            return candidates[0]
        if len(candidates) > 1:
            return None
    return None
