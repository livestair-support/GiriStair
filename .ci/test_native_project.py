import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

from native_project import (
    CONTAINER_ENTITLEMENT, ENVIRONMENT_ENTITLEMENT, SERVICES_ENTITLEMENT, SYNC_INFO_KEY,
    generate, verify_account_sync_ipa,
)


class NativeProjectTest(unittest.TestCase):
    def root(self, directory):
        root = Path(directory)
        (root / ".ci").mkdir()
        (root / ".ci/app_config.json").write_text(json.dumps({"bundle_id": "com.livestair.giristair"}))
        (root / "assets/brand/source").mkdir(parents=True)
        (root / "assets/brand/source/wordmark.jpg").write_bytes(b"original supplied wordmark")
        (root / "native").mkdir()
        return root

    def test_upgrade_preserves_container_identity_and_removes_flutter_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.root(directory)
            project = json.loads(generate(root, "24").read_text())
            target = project["targets"]["GiriStair"]
            settings = target["settings"]["base"]
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "com.livestair.giristair")
            self.assertEqual(settings["CURRENT_PROJECT_VERSION"], "24")
            with (root / "build/native/Info.plist").open("rb") as source:
                info = plistlib.load(source)
            self.assertEqual(info["CFBundleVersion"], "24")
            self.assertEqual(info["UILaunchStoryboardName"], "LaunchScreen")
            self.assertNotIn("UIMainStoryboardFile", info)
            self.assertNotIn("UISceneConfigurations", info["UIApplicationSceneManifest"])
            self.assertEqual(settings["GENERATE_INFOPLIST_FILE"], "NO")
            self.assertEqual(target["sources"][0]["path"], "GiriStair")
            self.assertFalse(any("Flutter" in value["path"] or "Pods" in value["path"] for value in target["sources"]))

    def test_provided_wordmark_is_copied_without_reencoding_or_modifying_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.root(directory)
            original = root / "assets/brand/source/wordmark.jpg"
            expected = hashlib.sha256(original.read_bytes()).digest()
            generate(root)
            self.assertEqual(hashlib.sha256(original.read_bytes()).digest(), expected)
            copied = root / "build/native/Brand.xcassets/BrandWordmark.imageset/wordmark.jpg"
            self.assertEqual(hashlib.sha256(copied.read_bytes()).digest(), expected)

    def test_invalid_build_numbers_cannot_generate_a_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.root(directory)
            for value in ["0", "-1", "1.1", "", "../24"]:
                with self.assertRaises(ValueError):
                    generate(root, value)
            self.assertFalse((root / "build").exists())

    def test_transparent_wordmark_is_used_while_source_is_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.root(directory)
            (root / "assets/brand/derived").mkdir()
            transparent = root / "assets/brand/derived/wordmark-transparent.png"
            transparent.write_bytes(b"transparent PNG derivative")
            generate(root)
            copied = root / "build/native/Brand.xcassets/BrandWordmark.imageset/wordmark.png"
            self.assertEqual(copied.read_bytes(), transparent.read_bytes())
            self.assertEqual((root / "assets/brand/source/wordmark.jpg").read_bytes(), b"original supplied wordmark")

    def test_ui_regression_runs_against_app_without_shipping_test_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            project = json.loads(generate(self.root(directory)).read_text())
            test = project["targets"]["GiriStairUITests"]
            self.assertEqual(test["type"], "bundle.ui-testing")
            self.assertEqual(test["dependencies"], [{"target": "GiriStair"}])
            self.assertEqual(test["sources"], [{"path": "UITests"}])
            scheme = project["schemes"]["GiriStair"]
            self.assertEqual(scheme["build"]["targets"]["GiriStairUITests"], ["test"])
            self.assertFalse(scheme["test"]["targets"][0]["parallelizable"])

    def test_account_sync_generation_selects_and_removes_cloudkit_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.root(directory)
            generated = root / "build/native"
            container = "iCloud.com.livestair.giristair"
            project = json.loads(generate(root, "24", account_sync_cloudkit=True).read_text())
            info = plistlib.loads((generated / "Info.plist").read_bytes())
            self.assertEqual(info[SYNC_INFO_KEY], container)
            entitlements = generated / "AccountSync.entitlements"
            self.assertEqual(plistlib.loads(entitlements.read_bytes()), {
                CONTAINER_ENTITLEMENT: [container], SERVICES_ENTITLEMENT: ["CloudKit"],
            })
            settings = project["targets"]["GiriStair"]["settings"]["base"]
            signing_path = root / "native" / settings["CODE_SIGN_ENTITLEMENTS"]
            self.assertTrue(signing_path.samefile(entitlements))

            project = json.loads(generate(root, "25").read_text())
            self.assertNotIn(SYNC_INFO_KEY, plistlib.loads((generated / "Info.plist").read_bytes()))
            self.assertFalse(entitlements.exists())
            self.assertNotIn("CODE_SIGN_ENTITLEMENTS", project["targets"]["GiriStair"]["settings"]["base"])

    def test_enabled_ipa_requires_build_identity_marker_and_signed_cloudkit_access(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa_dir = Path(directory)
            bundle_id = "com.livestair.giristair"
            container = f"iCloud.{bundle_id}"
            info = {
                "CFBundleIdentifier": bundle_id, "CFBundleShortVersionString": "0.36",
                "CFBundleVersion": "24", SYNC_INFO_KEY: container,
            }
            entitlements = {CONTAINER_ENTITLEMENT: [container], SERVICES_ENTITLEMENT: ["CloudKit"]}

            def verify(info_values, entitlement_values):
                with ZipFile(ipa_dir / "GiriStair.ipa", "w") as ipa:
                    ipa.writestr("Payload/GiriStair.app/Info.plist", plistlib.dumps(info_values))

                def run(command, *, check, stdout=None):
                    if command[0] == "/usr/bin/ditto":
                        with ZipFile(command[3]) as ipa:
                            ipa.extractall(command[4])
                        return subprocess.CompletedProcess(command, 0)
                    self.assertEqual(command[:-1], ["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml"])
                    self.assertTrue(command[-1].endswith("/Payload/GiriStair.app"))
                    return subprocess.CompletedProcess(command, 0, stdout=plistlib.dumps(entitlement_values))

                with patch("native_project.subprocess.run", side_effect=run):
                    verify_account_sync_ipa(ipa_dir, bundle_id, "0.36", "24")

            verify(info, entitlements)
            with self.assertRaisesRegex(ValueError, SYNC_INFO_KEY):
                verify({key: value for key, value in info.items() if key != SYNC_INFO_KEY}, entitlements)
            with self.assertRaisesRegex(ValueError, "CFBundleVersion"):
                verify({**info, "CFBundleVersion": "23"}, entitlements)
            with self.assertRaisesRegex(ValueError, "Info.plistの形式"):
                verify([], entitlements)
            with self.assertRaisesRegex(ValueError, "iCloudコンテナ"):
                verify(info, {**entitlements, CONTAINER_ENTITLEMENT: []})
            with self.assertRaisesRegex(ValueError, "iCloudコンテナ"):
                verify(info, {**entitlements, CONTAINER_ENTITLEMENT: container})
            with self.assertRaisesRegex(ValueError, "CloudKitの権限"):
                verify(info, {**entitlements, SERVICES_ENTITLEMENT: ["CloudDocuments"]})
            with self.assertRaisesRegex(ValueError, "CloudKitの権限"):
                verify(info, {**entitlements, SERVICES_ENTITLEMENT: "CloudKit"})
            with self.assertRaisesRegex(ValueError, "entitlementsの形式"):
                verify(info, [])
            with self.assertRaisesRegex(ValueError, "Production"):
                verify(info, {**entitlements, ENVIRONMENT_ENTITLEMENT: "Development"})


if __name__ == "__main__":
    unittest.main()
