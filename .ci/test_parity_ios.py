from contextlib import redirect_stderr, redirect_stdout
import io
import subprocess
import unittest
from unittest.mock import patch

from parity_ios import choose_phone, run, start_phone


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


if __name__ == "__main__":
    unittest.main()
