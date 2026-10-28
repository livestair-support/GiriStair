import unittest

from parity_ios import choose_phone


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


if __name__ == "__main__":
    unittest.main()
