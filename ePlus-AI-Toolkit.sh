#!/bin/sh
# One-click Zorin OS / Linux launcher for ePlus AI Toolkit.
# Opens the Textual TUI directly; Steps 2-5 always require explicit confirmation.
set -eu

SCRIPT_PATH=$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
cd "$SCRIPT_DIR"

if [ -t 0 ] && [ -t 1 ]; then
  exec /bin/sh "$SCRIPT_DIR/run-linux.sh" "$@"
fi

RUNNER_CMD="cd \"$SCRIPT_DIR\" && /bin/sh \"$SCRIPT_DIR/run-linux.sh\"; rc=\$?; if [ \"\$rc\" -ne 0 ]; then printf '\nExited with code %s. Press Enter to close...\n' \"\$rc\"; read -r _; fi"

if command -v gnome-terminal >/dev/null 2>&1; then
  exec gnome-terminal --title="ePlus AI Toolkit" --geometry=110x35 -- /bin/sh -c "$RUNNER_CMD"
elif command -v x-terminal-emulator >/dev/null 2>&1; then
  exec x-terminal-emulator -e /bin/sh -c "$RUNNER_CMD"
elif command -v xfce4-terminal >/dev/null 2>&1; then
  exec xfce4-terminal --title="ePlus AI Toolkit" --geometry=110x35 -e "/bin/sh -c '$RUNNER_CMD'"
else
  exec /bin/sh "$SCRIPT_DIR/run-linux.sh" "$@"
fi
