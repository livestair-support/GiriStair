"""Validate supplied artwork and native regeneration without Pillow or Flutter."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import tempfile
import unittest

import brand_assets
import prepare_project

ROOT = Path(__file__).resolve().parents[1]


def fixture(root):
    config = {
        "project_name": "giristair", "organization": "com.livestair",
        "bundle_id": "com.livestair.giristair", "display_name": "GiriStair",
        "minimum_ios": "15.5",
    }
    path = root / ".ci/app_config.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config))
    project = root / "ios/Runner.xcodeproj/project.pbxproj"
    project.parent.mkdir(parents=True, exist_ok=True)
    project.write_text("PRODUCT_BUNDLE_IDENTIFIER = com.livestair.giristair;\nIPHONEOS_DEPLOYMENT_TARGET = 15.5;\n")
    info = root / "ios/Runner/Info.plist"
    info.parent.mkdir(parents=True, exist_ok=True)
    info.write_bytes(plistlib.dumps({"CFBundleName": "giristair"}))
    gradle = root / "android/app/build.gradle.kts"
    gradle.parent.mkdir(parents=True, exist_ok=True)
    gradle.write_text('namespace = "com.livestair.giristair"\napplicationId = "com.livestair.giristair"\n')
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application android:label="giristair" android:icon="@mipmap/ic_launcher">'
        '<activity android:name=".MainActivity" android:theme="@style/LaunchTheme"/>'
        '</application></manifest>'
    )


class BrandAssetsTest(unittest.TestCase):
    def test_originals_and_applied_native_images_match_the_manifest(self):
        brand_assets.check_brand_assets(ROOT)
        catalog = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        entries = json.loads((catalog / "Contents.json").read_text())["images"]
        for entry in entries:
            with self.subTest(entry=entry):
                data = (catalog / entry["filename"]).read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                pixels = int(float(entry["size"].split("x")[0]) * int(entry["scale"][0]))
                self.assertEqual(struct.unpack(">II", data[16:24]), (pixels, pixels))
                self.assertEqual(data[25], 2, "App Store icons must have RGB pixels without alpha")

    def test_project_preparation_restores_the_brand_after_native_assets_are_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture(root)
            package = root / "assets/brand/native-assets.zip"
            package.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "assets/brand/native-assets.zip", package)
            source = root / "lib/main.dart"
            source.parent.mkdir()
            source.write_text("existing application")
            prepare_project.prepare(root)
            icon = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
            expected = hashlib.sha256(icon.read_bytes()).hexdigest()
            icon.unlink()
            (root / "ios/Runner/Base.lproj/LaunchScreen.storyboard").unlink()
            prepare_project.prepare(root)
            self.assertEqual(hashlib.sha256(icon.read_bytes()).hexdigest(), expected)
            launch = (root / "ios/Runner/Base.lproj/LaunchScreen.storyboard").read_text()
            self.assertIn('contentMode="scaleAspectFit"', launch)
            manifest = (root / "android/app/src/main/AndroidManifest.xml").read_text()
            self.assertIn('@style/BrandLaunchTheme', manifest)
            self.assertIn('@mipmap/ic_launcher_round', manifest)
            self.assertTrue((root / "android/app/src/main/res/values-v31/brand_launch.xml").is_file())
            self.assertEqual(source.read_text(), "existing application")


if __name__ == "__main__":
    unittest.main()
