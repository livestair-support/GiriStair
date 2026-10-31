import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

from native_project import generate


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


if __name__ == "__main__":
    unittest.main()
