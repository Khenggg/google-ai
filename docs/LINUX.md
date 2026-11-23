# Linux (Zorin OS / Ubuntu) & One-Click Launchers

This port keeps full upstream compatibility for Windows (`run-all.ps1`) and macOS (`run-macos.sh`), while adding native Linux support, Android 16/17 compatibility, event-driven waits, and one-click desktop launchers.

## One-Click Launch

- **Linux / Zorin OS:** Run `sh install-linux-app.sh` once to add **ePlus AI Toolkit** to the Application Menu and install the `eplus-ai-toolkit` command, or launch `./ePlus-AI-Toolkit.sh` directly.
- **Windows:** Double-click `ePlus-AI-Toolkit.cmd` (launches `run-all.ps1` into the Textual TUI without running any paid stage automatically).

## Linux CLI Modes

```sh
sh run-linux.sh                  # Full 6-step Textual TUI (no automatic checkout)
sh run-linux.sh --diagnose       # Read-only host, ADB, USB, Play Store and Google One check
sh run-linux.sh --check          # Step 0: ADB, root, frida-server and Play Store preflight
sh run-linux.sh --list           # Step 1: Read-only offer query (no checkout)
sh run-linux.sh --cleanup-phone  # Stop frida-server and remove temporary files on Android
```

## Key Port Highlights

- **Direct USB Android priority:** Automatically prefers a direct USB transport over TCP/Wi-Fi aliases of the same device `boot_id` or local emulators.
- **Android 16/17 (SDK 36+) Frida compatibility:** Automatically selects Frida `17.27.4` with the bundled `assets/frida/java-bridge-17.js` shim (patched for Android 17 ART `FindFieldJNI`), while preserving Frida `16.5.9` on Android 15 and older.
- **Android 14+ safer DEX loading:** Enforces `chmod 444` on `/data/local/tmp/module_521.apk`.
- **Event-driven step waits:** Exits Frida wait loops promptly after `list_only`, `launched`, or terminal errors instead of sleeping a fixed 90 seconds, while keeping all account/device/checkout confirmations intact.

## Attribution & Safety

Upstream credits remain unchanged: original author [@gylive](https://github.com/gylive/google-ultra) and maintainer [@hoangsvit](https://github.com/hoangsvit/google-ai). See `THIRD_PARTY_NOTICES.md`, `DISCLAIMER.md`, and `SECURITY.md`. Steps 2-5 may request real Google Play charges and always require explicit user confirmation.
