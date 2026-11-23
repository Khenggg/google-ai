#!/bin/sh
# Native Linux (Zorin OS / Ubuntu) launcher for ePlus AI Toolkit.
# Checkout requires explicit TUI approval; Steps 2-5 never run automatically.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  printf '%s\n' \
    "ePlus AI Toolkit — Linux / Zorin OS (Textual, Steps 0–5)" \
    "Usage: sh run-linux.sh [--diagnose | --check | --list | --cleanup-phone | --step N] [--sequence] [--serial ID] [--frida VER] [--debug] [--help]" \
    "  (no flags)      Textual dashboard, including optional confirmed checkout" \
    "  --diagnose      Read-only host/ADB/USB/Google One check (no changes)" \
    "  --check         Step 0: Android/root/Frida environment preflight" \
    "  --list          Step 1: Query available offers (no checkout)" \
    "  --cleanup-phone Stop frida-server and remove temp files on Android" \
    "  --step N        Open the dashboard with Step 0..5 selected" \
    "  --sequence      Open dashboard with guided sequence controls" \
    "  --serial ID     Target a specific ADB device serial (e.g. OnePlus 13T)" \
    "  --frida VER     Pin Frida version (default: auto 17.27.4 on Android 16/17, else 16.5.9)" \
    "  --debug         Open dashboard with technical log visible" \
    "  --help          Display usage" \
    "Steps 2–5 can submit real charges after explicit TUI confirmations."
}

MODE="tui"
STEP_ARG=""
SEQUENCE_FLAG=""
DEBUG_FLAG=""
SERIAL_ARG=""
FRIDA_ARG="${EPLUS_FRIDA_VERSION:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --diagnose)
      MODE="diagnose"
      shift
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --list)
      MODE="list"
      shift
      ;;
    --cleanup-phone)
      MODE="cleanup"
      shift
      ;;
    --sequence)
      SEQUENCE_FLAG="--sequence"
      shift
      ;;
    --debug)
      DEBUG_FLAG="--debug"
      shift
      ;;
    --step)
      if [ "$#" -lt 2 ]; then usage >&2; exit 2; fi
      case "$2" in
        0|1|2|3|4|5) STEP_ARG="$2" ;;
        *) usage >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --serial)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage >&2; exit 2; fi
      SERIAL_ARG="$2"
      shift 2
      ;;
    --frida)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage >&2; exit 2; fi
      FRIDA_ARG="$2"
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$(uname -s)" != "Linux" ]; then
  printf '%s\n' "This launcher requires Linux; on macOS use sh run-macos.sh, on Windows use .\\run-all.ps1" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1 ||
   ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
  printf '%s\n' "Install Python 3.10+ to run this toolkit." >&2
  exit 2
fi

find_adb() {
  if [ -n "${ADB_PATH:-}" ] && [ -x "$ADB_PATH" ]; then
    printf '%s\n' "$ADB_PATH"
    return 0
  fi
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi
  cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
  for candidate in \
    "$PWD/platform-tools/adb" \
    "$cache_home/oneplus13t/platform-tools/adb" \
    "$cache_home/google-ai/platform-tools/adb" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Android/Sdk/platform-tools/adb" \
    "/usr/local/bin/adb" \
    "/usr/bin/adb"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

find_uv() {
  if [ -n "${UV_BIN:-}" ] && [ -x "$UV_BIN" ]; then
    printf '%s\n' "$UV_BIN"
    return 0
  fi
  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return 0
  fi
  for candidate in \
    "$HOME/.local/bin/uv" \
    "$HOME/.cargo/bin/uv"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

detect_target_frida() {
  if [ -n "$FRIDA_ARG" ]; then
    printf '%s\n' "$FRIDA_ARG"
    return 0
  fi
  if [ -n "${ADB_BIN:-}" ] && [ -x "${ADB_BIN:-}" ]; then
    sdk="$(python3 - "$ADB_BIN" "$SERIAL_ARG" <<'PY' 2>/dev/null || true
import subprocess, sys
from device_selector import auto_select_device
adb, preferred = sys.argv[1], sys.argv[2] or None
serial = auto_select_device(adb, preferred=preferred, prefer_usb=True)
if not serial:
    raise SystemExit(0)
res = subprocess.run([adb, "-s", serial, "shell", "getprop", "ro.build.version.sdk"],
                     capture_output=True, text=True, timeout=5)
if res.returncode == 0:
    print(res.stdout.strip())
PY
)"
    case "$sdk" in
      ''|*[!0-9]*) ;;
      *)
        if [ "$sdk" -ge 36 ]; then
          printf '%s\n' "17.27.4"
          return 0
        fi
        ;;
    esac
  fi
  printf '%s\n' "16.5.9"
}

ensure_venv() {
  target_frida="$1"
  if [ "$target_frida" = "16.5.9" ]; then
    venv_dir=".venv"
  else
    venv_dir=".venv-frida17"
  fi
  uv_cmd="$(find_uv || true)"
  if [ ! -x "$venv_dir/bin/python" ]; then
    if python3 -m ensurepip --version >/dev/null 2>&1; then
      python3 -m venv "$venv_dir"
    elif [ -n "$uv_cmd" ]; then
      "$uv_cmd" venv --python python3 --seed "$venv_dir"
    else
      printf '%s\n' "Python ensurepip/venv is unavailable and uv was not found. Install python3-venv and python3-pip (or uv)." >&2
      exit 2
    fi
  fi
  PYTHON="$PWD/$venv_dir/bin/python"
  if ! "$PYTHON" -c "import importlib.metadata as m, sys; import textual, frida; assert m.version('frida') == sys.argv[1]" "$target_frida" >/dev/null 2>&1; then
    cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
    local_whl="$cache_home/oneplus13t/frida/frida-${target_frida}-cp37-abi3-manylinux1_x86_64.whl"
    frida_pkg="frida==${target_frida}"
    if [ -f "$local_whl" ]; then
      frida_pkg="$local_whl"
    fi
    if [ -n "$uv_cmd" ]; then
      "$uv_cmd" pip install --python "$PYTHON" -r requirements-tui.txt "$frida_pkg"
    elif "$PYTHON" -m pip --version >/dev/null 2>&1; then
      "$PYTHON" -m pip install --disable-pip-version-check -r requirements-tui.txt "$frida_pkg"
    else
      printf '%s\n' "Neither pip nor uv is available to install textual and $frida_pkg into $venv_dir." >&2
      exit 2
    fi
  fi
}

ADB_BIN="$(find_adb || true)"
if [ -z "$ADB_BIN" ]; then
  ADB_BIN="$(python3 -c 'import setup_env; print(setup_env.download_linux_platform_tools())' 2>/dev/null || true)"
fi
if [ -n "$ADB_BIN" ] && [ -x "$ADB_BIN" ]; then
  export ADB_PATH="$ADB_BIN"
  export PATH="$(dirname -- "$ADB_BIN"):$PATH"
elif [ "$MODE" != "diagnose" ] && [ "$MODE" != "tui" ]; then
  printf '%s\n' "ADB not found. Install Android SDK Platform-Tools or set ADB_PATH." >&2
  exit 2
fi

if [ -n "$SERIAL_ARG" ]; then
  export EPLUS_ADB_SERIAL="$SERIAL_ARG"
fi

TARGET_FRIDA="$(detect_target_frida)"
export EPLUS_FRIDA_VERSION="$TARGET_FRIDA"

ensure_venv "$TARGET_FRIDA"
export PYTHONIOENCODING=utf-8:backslashreplace
export PYTHONUTF8=1

case "$MODE" in
  diagnose)
    exec "$PYTHON" - "$SERIAL_ARG" <<'PY'
import sys
from device_diagnostics import inspect_connection, locate_adb
from device_selector import auto_select_device

preferred = sys.argv[1] or None
adb = locate_adb("linux")
selected = preferred
if not selected and adb:
    selected = auto_select_device(adb, prefer_usb=True)
diag = inspect_connection("linux", serial=selected)
print(diag.headline)
for line in diag.details:
    print("  " + line)
print("Next: " + diag.guidance)
sys.exit(0 if diag.status == "connected" else 1)
PY
    ;;
  check)
    if [ -n "$SERIAL_ARG" ]; then
      exec "$PYTHON" linux_runner.py --step 0 --serial "$SERIAL_ARG"
    fi
    exec "$PYTHON" linux_runner.py --step 0
    ;;
  list)
    if [ -n "$SERIAL_ARG" ]; then
      exec "$PYTHON" linux_runner.py --step 1 --serial "$SERIAL_ARG"
    fi
    exec "$PYTHON" linux_runner.py --step 1
    ;;
  cleanup)
    exec "$PYTHON" - "$ADB_BIN" "$SERIAL_ARG" <<'PY'
import subprocess, sys
from device_selector import auto_select_device

adb, preferred = sys.argv[1], sys.argv[2] or None
serial = auto_select_device(adb, preferred=preferred, prefer_usb=True)
if not serial:
    print("No unique online Android device found.", file=sys.stderr)
    raise SystemExit(1)
subprocess.run(
    [adb, "-s", serial, "shell",
     "su -c 'pkill -f /data/local/tmp/frida-server || pkill -f frida-server || true; "
     "rm -f /data/local/tmp/frida-server /data/local/tmp/module_521.apk'"],
    check=False, timeout=20,
)
pid = subprocess.run(
    [adb, "-s", serial, "shell", "pidof frida-server || true"],
    capture_output=True, text=True, timeout=10,
).stdout.strip()
print(f"Cleaned Android device {serial}: frida-server running={bool(pid)}")
raise SystemExit(1 if pid else 0)
PY
    ;;
  tui)
    set -- "$PYTHON" tui.py
    if [ -n "$STEP_ARG" ]; then set -- "$@" --step "$STEP_ARG"; fi
    if [ -n "$SEQUENCE_FLAG" ]; then set -- "$@" "$SEQUENCE_FLAG"; fi
    if [ -n "$DEBUG_FLAG" ]; then set -- "$@" "$DEBUG_FLAG"; fi
    exec "$@"
    ;;
esac
exit 2
