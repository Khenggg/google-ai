"""Linux (Zorin OS) port tests. All Android/checkout interactions are mocked."""
import base64
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import device_diagnostics as diag
import device_selector as selector
import linux_runner
import ultra0
from tui_core import command_for_step


class LinuxStageAdapterTests(unittest.TestCase):
    def test_android_details_query_uses_selected_device(self):
        result = subprocess.CompletedProcess([], 0, "17\n37\narm64-v8a\nPKX110\n", "")
        with patch("linux_runner.subprocess.run", return_value=result) as run:
            with patch("builtins.print") as output:
                linux_runner.show_android_details("/tools/adb", "usb-phone-01")
        self.assertEqual(run.call_args.args[0][:4], ["/tools/adb", "-s", "usb-phone-01", "shell"])
        output.assert_any_call("Android 17 (SDK 37), ABI arm64-v8a", flush=True)
        output.assert_any_call("Model PKX110", flush=True)

    def test_six_stage_mapping_and_no_force(self):
        offers = {
            2: ("pro12", "12months-eft", False),
            3: ("pro6", "6months-eft", True),
            4: ("pro6b", "6months-eft-2", True),
            5: ("pro6c", "6months-eft-ss-2026", True),
        }
        for step, (plan, expected, stacking) in offers.items():
            with self.subTest(step=step):
                cmd = linux_runner.stage_command(step, "usb-phone-01", "alice@example.com", "python")
                self.assertEqual(cmd[cmd.index("--plan") + 1], plan)
                self.assertEqual(linux_runner.STAGES[step][1], expected)
                self.assertEqual("--stack" in cmd, stacking)
                self.assertIn("--no-switch", cmd)
                self.assertIn("--no-add", cmd)
                self.assertNotIn("--force", cmd)
        for step in (-1, 6, True, "2"):
            with self.assertRaises(ValueError):
                linux_runner.stage_command(step, "usb-phone-01")

    def test_list_never_opens_checkout(self):
        cmd = linux_runner.stage_command(1, "usb-phone-01")
        for flag in ("--list", "--no-add", "--no-switch"):
            self.assertIn(flag, cmd)
        for forbidden in ("--force", "--stack", "--confirmed"):
            self.assertNotIn(forbidden, cmd)

    def test_usb_device_is_prioritized_over_emulator_on_linux(self):
        devices_l = subprocess.CompletedProcess(
            [], 0,
            "List of devices attached\n"
            "emulator-5554 device transport_id:1\n"
            "usb-phone-01 device usb:1-2 product:PKX110 model:PKX110 transport_id:2\n",
            "",
        )
        with patch.object(selector, "boot_uuid", side_effect=lambda _a, s: "11111111-2222-3333-4444-555555555555" if s == "usb-phone-01" else "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), \
             patch.object(selector, "adb_command", return_value=devices_l):
            chosen = selector.auto_select_device(
                "adb", serials=["emulator-5554", "usb-phone-01"], prefer_usb=True
            )
        self.assertEqual(chosen, "usb-phone-01")

    def test_usb_alias_is_preferred_among_same_device_transports(self):
        devices_l = subprocess.CompletedProcess(
            [], 0,
            "List of devices attached\n"
            "usb-phone-01 device usb:1-2 product:PKX110 model:PKX110 transport_id:1\n"
            "127.0.0.1:5556 device product:PKX110 model:PKX110 transport_id:2\n"
            "192.168.200.27:45845 device product:PKX110 model:PKX110 transport_id:5\n",
            "",
        )
        with patch.object(selector, "boot_uuid", return_value="11111111-2222-3333-4444-555555555555"), \
             patch.object(selector, "adb_command", return_value=devices_l):
            chosen = selector.auto_select_device(
                "adb",
                serials=["127.0.0.1:5556", "192.168.200.27:45845", "usb-phone-01"],
                prefer_usb=True,
            )
        self.assertEqual(chosen, "usb-phone-01")

    def test_frida_17_prepends_java_bridge_shim(self):
        with patch.dict(os.environ, {"EPLUS_FRIDA_VERSION": "17.27.4"}):
            script = ultra0.build_js(plan="pro12", list_only=True)
        self.assertIn("globalThis.Java", script)
        self.assertIn("12months-eft", script)
        self.assertGreater(len(script), len(ultra0.FRIDA_JS) + 10000)

    def test_module_apk_is_marked_readonly_for_android_14_plus(self):
        calls = []
        def fake_sh(*args, **kwargs):
            calls.append(args)
            if args == ("shell", f"ls {ultra0.MODULE_REMOTE} 2>/dev/null"):
                return ultra0.MODULE_REMOTE
            return ""
        with patch.object(ultra0, "sh", side_effect=fake_sh):
            ultra0.ensure_module_apk()
        self.assertIn(("shell", f"chmod 444 {ultra0.MODULE_REMOTE}"), calls)

    def test_run_trial_exits_early_when_list_only_or_launched_event_arrives(self):
        from unittest.mock import MagicMock
        for mode, event_payload in (
            (True, {"ev": "list_only", "id": "12months-eft"}),
            (False, {"ev": "launched", "code": 0}),
        ):
            with self.subTest(list_only=mode):
                device = MagicMock()
                session = MagicMock()
                script = MagicMock()
                device.attach.return_value = session
                session.create_script.return_value = script
                handlers = {}
                script.on.side_effect = lambda name, fn: handlers.setdefault(name, fn)
                script.load.side_effect = lambda: handlers["message"](
                    {"type": "send", "payload": event_payload}, None
                )
                start = time.monotonic()
                with patch.object(ultra0, "get_target_frida_device", return_value=device):
                    report = ultra0.run_trial(123, wait=90, list_only=mode)
                elapsed = time.monotonic() - start
                self.assertLess(elapsed, 5.0)
                if not mode:
                    self.assertEqual(report["launched"]["code"], 0)

    def test_tui_core_linux_uses_linux_runner_and_gates_checkout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "linux_runner.py").write_text("# mock", encoding="utf-8")
            with patch("tui_core.sys.platform", "linux"):
                for step in range(6):
                    command = command_for_step(step, root, account="alice@example.com", device="usb-phone-01")
                    self.assertEqual(command[0], sys.executable)
                    self.assertTrue(command[1].endswith("linux_runner.py"))
                    self.assertEqual(command[command.index("--step") + 1], str(step))
                    self.assertEqual("--confirmed" in command, step >= 2)
                    self.assertEqual("--active-confirmed" in command, step >= 3)
                    if step >= 2:
                        self.assertEqual(command[command.index("--expected-device") + 1], "usb-phone-01")
                        self.assertEqual(command[command.index("--expected-account") + 1], "alice@example.com")

    def test_linux_diagnostics_reports_zorin_host_and_guidance(self):
        with patch.object(diag, "locate_adb", return_value=None), \
             patch.object(diag.metadata, "version", return_value="16.5.9"):
            found = diag.inspect_connection("linux")
        self.assertEqual(found.status, "missing_adb")
        self.assertIn("Host: Linux / Zorin OS", found.details)
        self.assertIn("run-linux.sh", found.guidance)

    def test_temporary_su_binary_is_detected_on_physical_android(self):
        def fake_sh(*args, **kwargs):
            cmd = " ".join(args)
            if cmd == "shell id":
                return "uid=2000(shell)"
            if cmd == "root":
                return "adbd cannot run as root in production builds"
            if "/data/local/tmp/su -c id" in cmd:
                return "uid=0(root) gid=0(root)"
            return ""
        with patch.object(ultra0, "sh", side_effect=fake_sh), \
             patch.object(ultra0.time, "sleep"):
            ultra0.ensure_root()
            self.assertEqual(ultra0.SU_BIN, "/data/local/tmp/su")
            ultra0.SU_BIN = ""

    def test_launcher_syntax_and_safety_warnings(self):
        root = Path(__file__).resolve().parents[1]
        for name in ("run-linux.sh", "ePlus-AI-Toolkit.sh", "install-linux-app.sh"):
            launcher = root / name
            self.assertTrue(launcher.is_file(), f"Missing {name}")
            check = subprocess.run(["sh", "-n", str(launcher)], capture_output=True, text=True)
            self.assertEqual(check.returncode, 0, f"{name}: {check.stderr}")
        src = (root / "run-linux.sh").read_text(encoding="utf-8")
        self.assertIn("Steps 2–5 can submit real charges", src)
        self.assertNotIn("--force", src)
        win_cmd = root / "ePlus-AI-Toolkit.cmd"
        self.assertTrue(win_cmd.is_file())
        win_src = win_cmd.read_text(encoding="utf-8")
        self.assertIn("run-all.ps1", win_src)
        self.assertNotIn("-Force", win_src)

    def test_linux_adapter_errors_do_not_leak_stack_trace(self):
        output = io.StringIO()
        errors = io.StringIO()
        with patch.dict(os.environ, {"EPLUS_TUI": "1"}), \
             patch("linux_runner.preflight", side_effect=RuntimeError("No online Android device. Check adb devices.")), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            self.assertEqual(linux_runner.main(["--step", "1"]), 1)
        self.assertIn("Android device is not connected", errors.getvalue())
        self.assertIn("EPLUS_ISSUE:device_missing", output.getvalue())


class LinuxTuiTests(unittest.IsolatedAsyncioTestCase):
    async def test_linux_tui_renders_at_90x20_and_110x35_without_auto_run(self):
        from textual.widgets import Select
        from tui import GoogleAITUI, Approval
        for size in ((90, 20), (110, 35)):
            with self.subTest(size=size), tempfile.TemporaryDirectory() as temp:
                with patch("tui.is_linux_platform", return_value=True), \
                     patch("tui.is_macos_platform", return_value=False):
                    app = GoogleAITUI(repo=Path(temp), selected_step=2)
                with patch("tui.subprocess.Popen") as child:
                    async with app.run_test(size=size) as pilot:
                        self.assertTrue(app.posix_mode)
                        self.assertTrue(app.linux_mode)
                        self.assertEqual(app.query_one("#step", Select).value, 2)
                        self.assertEqual(len(app.query("#workflow .workflow-step")), 6)
                        self.assertFalse(app.busy)
                        app._offer_check_ready = True
                        app._confirm_stage(2, False)
                        await pilot.pause()
                        self.assertIsInstance(app.screen, Approval)
                    child.assert_not_called()


if __name__ == "__main__":
    unittest.main()
