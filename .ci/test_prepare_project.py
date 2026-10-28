"""Check bootstrap safety without needing Flutter or a signing account."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    "prepare_project", Path(__file__).with_name("prepare_project.py")
)
assert SPEC is not None and SPEC.loader is not None
prepare_project = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare_project)


CONFIG = {
    "project_name": "giristair",
    "display_name": "GiriStair",
    "organization": "com.livestair",
    "bundle_id": "com.livestair.giristair",
    "minimum_ios": "15.0",
}


def native_fixture(root: Path, deployment_target: str = "13.0") -> None:
    project = root / "ios/Runner.xcodeproj/project.pbxproj"
    project.parent.mkdir(parents=True)
    project.write_text(
        "PRODUCT_BUNDLE_IDENTIFIER = com.livestair.giristair;\n"
        f"IPHONEOS_DEPLOYMENT_TARGET = {deployment_target};\n",
        encoding="utf-8",
    )
    info = root / "ios/Runner/Info.plist"
    info.parent.mkdir(parents=True)
    info.write_bytes(plistlib.dumps({"CFBundleDisplayName": "giristair"}))
    gradle = root / "android/app/build.gradle.kts"
    gradle.parent.mkdir(parents=True)
    gradle.write_text(
        'namespace = "com.livestair.giristair"\n'
        'applicationId = "com.livestair.giristair"\n',
        encoding="utf-8",
    )
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    manifest.parent.mkdir(parents=True)
    manifest.write_text(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application android:label="giristair"/></manifest>',
        encoding="utf-8",
    )


class PrepareProjectTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        config_path = self.root / ".ci/app_config.json"
        config_path.parent.mkdir()
        config_path.write_text(json.dumps(CONFIG), encoding="utf-8")

    def test_bootstrap_preserves_application_and_dependency_files(self) -> None:
        protected = {
            "lib/main.dart": "Application source must survive.\n",
            "pubspec.yaml": "Existing dependencies must survive.\n",
            "pubspec.lock": "Existing lockfile must survive.\n",
        }
        for name, contents in protected.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")

        def generate(arguments: list[str], *, check: bool) -> None:
            self.assertTrue(check)
            self.assertIn("--no-pub", arguments)
            native_fixture(Path(arguments[-1]))
            generated_main = Path(arguments[-1]) / "lib/main.dart"
            generated_main.parent.mkdir()
            generated_main.write_text("template source", encoding="utf-8")

        with mock.patch.object(prepare_project.subprocess, "run", side_effect=generate):
            prepare_project.prepare(self.root)
        for name, contents in protected.items():
            self.assertEqual((self.root / name).read_text(encoding="utf-8"), contents)
        self.assertTrue((self.root / "ios/Runner/Info.plist").is_file())
        self.assertTrue((self.root / "android/app/build.gradle.kts").is_file())

    def test_existing_native_project_is_not_replaced(self) -> None:
        native_fixture(self.root, deployment_target="18.0")
        custom = self.root / "ios/Runner/custom.swift"
        custom.write_text("custom native code", encoding="utf-8")
        with mock.patch.object(prepare_project.subprocess, "run") as generate:
            prepare_project.prepare(self.root)
            generate.assert_not_called()
        self.assertEqual(custom.read_text(encoding="utf-8"), "custom native code")
        project = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 18.0;", project.read_text())

    def test_signing_id_mismatch_fails_before_generation(self) -> None:
        with mock.patch.dict(os.environ, {"BUNDLE_ID": "com.other.app"}):
            with mock.patch.object(prepare_project.subprocess, "run") as generate:
                with self.assertRaisesRegex(ValueError, "Bundle ID"):
                    prepare_project.prepare(self.root)
                generate.assert_not_called()
        self.assertFalse((self.root / "ios").exists())

    def test_existing_wrong_android_id_is_rejected(self) -> None:
        native_fixture(self.root)
        gradle = self.root / "android/app/build.gradle.kts"
        gradle.write_text('applicationId = "com.other.app"', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "applicationId"):
            prepare_project.prepare(self.root)


if __name__ == "__main__":
    unittest.main()
