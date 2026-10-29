from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from parity_ios import (
    choose_phone, run, start_phone, verify_font_diagnostics, wait_for_preview_ready,
)


class SimulatorSelectionTest(unittest.TestCase):
    def test_uses_available_current_runtime_and_preferred_phone(self):
        runtime, device = choose_phone({"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
                {"name": "iPhone 16", "isAvailable": True, "udid": "old"},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                {"name": "iPhone 17 Pro", "isAvailable": True, "udid": "pro"},
                {"name": "iPhone 16", "isAvailable": True, "udid": "preferred"},
                {"name": "iPhone 17", "isAvailable": False, "udid": "unavailable"},
            ],
        }})
        self.assertTrue(runtime.endswith("iOS-26-2"))
        self.assertEqual(device["udid"], "preferred")

    def test_refuses_older_runtime_instead_of_claiming_glass_was_checked(self):
        with self.assertRaisesRegex(RuntimeError, "iOS 26"):
            choose_phone({"devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
                    {"name": "iPhone 16", "isAvailable": True},
                ],
            }})

    def test_ignores_ipad_and_unavailable_devices(self):
        with self.assertRaisesRegex(RuntimeError, "iPhone"):
            choose_phone({"devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                    {"name": "iPad Pro", "isAvailable": True},
                    {"name": "iPhone 17", "isAvailable": False},
                ],
            }})

    def test_does_not_boot_a_phone_already_booting_or_booted(self):
        with patch("parity_ios.run") as command:
            start_phone({"state": "Booting", "udid": "phone"})
            start_phone({"state": "Booted", "udid": "phone"})
            command.assert_not_called()
            start_phone({"state": "Shutdown", "udid": "phone"})
            command.assert_called_once_with("xcrun", "simctl", "boot", "phone")

    def test_timeout_preserves_boot_progress_and_failure_stderr(self):
        error = subprocess.TimeoutExpired(
            ["xcrun", "simctl", "bootstatus"], 600,
            output=b"Waiting for SpringBoard", stderr=b"Simulator diagnostic",
        )
        output = io.StringIO()
        with patch("parity_ios.subprocess.run", side_effect=error):
            with redirect_stdout(io.StringIO()), redirect_stderr(output):
                with self.assertRaises(subprocess.TimeoutExpired):
                    run("xcrun", "simctl", "bootstatus", timeout=600)
        self.assertIn("Waiting for SpringBoard", output.getvalue())
        self.assertIn("Simulator diagnostic", output.getvalue())


class PreviewReadinessTest(unittest.TestCase):
    def test_only_the_requested_screen_from_the_current_process_is_ready(self):
        replies = [
            subprocess.CompletedProcess([], 0, "GiriStairPreviewReady calendar"),
            subprocess.CompletedProcess([], 0, "GiriStairPreviewReady detail"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with patch("parity_ios.run", side_effect=replies) as command:
                with patch("parity_ios.time.sleep"):
                    wait_for_preview_ready("phone", 123, "detail", output)
            self.assertEqual(command.call_count, 2)
            for call in command.call_args_list:
                self.assertEqual(call.args[-1], "processIdentifier == 123")
            self.assertIn(
                "GiriStairPreviewReady detail",
                (output / "detail-ready.log").read_text(),
            )

    def test_requested_route_without_render_completion_cannot_be_a_screenshot(self):
        reply = subprocess.CompletedProcess([], 0, "GiriStairPreview detail")
        with tempfile.TemporaryDirectory() as directory:
            with patch("parity_ios.run", return_value=reply):
                with patch("parity_ios.time.monotonic", side_effect=[0, 0, 151]):
                    with patch("parity_ios.time.sleep"):
                        with self.assertRaisesRegex(RuntimeError, "refusing a startup screenshot"):
                            wait_for_preview_ready("phone", 123, "detail", Path(directory))


class FontDiagnosticsTest(unittest.TestCase):
    def font_log(self, family="Hiragino Sans"):
        fonts = {
            role: {"japaneseFamilyName": family, "basePostscriptName": ".SFUI-Regular"}
            for role in ("pageTitle", "sectionTitle", "formLabel", "input", "dateValue")
        }
        return "Runner (CoreText) GiriStairTypography " + json.dumps(fonts)

    def test_accepts_actual_ui_families_and_retains_diagnostics(self):
        fonts = verify_font_diagnostics(self.font_log())
        self.assertEqual(fonts["input"]["japaneseFamilyName"], "Hiragino Sans")

    def test_rejects_system_font_reconstruction_warning(self):
        warning = 'CoreText note: Client requested name ".SFUI-Bold", it will get TimesNewRomanPSMT rather than the intended font.'
        with self.assertRaisesRegex(RuntimeError, "Times New Roman"):
            verify_font_diagnostics(warning + "\n" + self.font_log())

    def test_rejects_mincho_fallback(self):
        with self.assertRaisesRegex(RuntimeError, "Unexpected Japanese UI font"):
            verify_font_diagnostics(self.font_log("Hiragino Mincho ProN"))

    def test_missing_diagnostics_cannot_claim_font_verification(self):
        with self.assertRaisesRegex(RuntimeError, "unverified"):
            verify_font_diagnostics("Runner launched")


if __name__ == "__main__":
    unittest.main()
