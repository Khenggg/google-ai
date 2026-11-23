#!/bin/sh
# One-click installer for Zorin OS / Ubuntu / Linux.
# Creates an Application Menu launcher (~/.local/share/applications/eplus-ai-toolkit.desktop)
# and CLI shortcut (~/.local/bin/eplus-ai-toolkit) pointing to this directory.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chmod +x "$SCRIPT_DIR/run-linux.sh" "$SCRIPT_DIR/ePlus-AI-Toolkit.sh" "$SCRIPT_DIR/linux_runner.py"

APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$APP_DIR" "$BIN_DIR"

DESKTOP_FILE="$APP_DIR/eplus-ai-toolkit.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=ePlus AI Toolkit
GenericName=Android Google AI Offer Diagnostics
Comment=Textual TUI for Google AI Pro Android diagnostics (OnePlus 13T / Linux)
Exec=$SCRIPT_DIR/ePlus-AI-Toolkit.sh
Path=$SCRIPT_DIR
Icon=utilities-terminal
Terminal=false
Categories=Utility;
Keywords=android;adb;frida;google-one;oneplus;
StartupNotify=true
EOF
chmod 755 "$DESKTOP_FILE"

ln -sf "$SCRIPT_DIR/ePlus-AI-Toolkit.sh" "$BIN_DIR/eplus-ai-toolkit"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi

printf '%s\n' \
  "Installed ePlus AI Toolkit 1-click launcher:" \
  "  Menu entry : $DESKTOP_FILE" \
  "  CLI command: $BIN_DIR/eplus-ai-toolkit" \
  "  Direct file: $SCRIPT_DIR/ePlus-AI-Toolkit.sh"
