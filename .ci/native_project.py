#!/usr/bin/env python3
"""Generate the independent SwiftUI iPhone project without Flutter tooling."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import plistlib
import shutil

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.4.0"
MINIMUM_IOS = "18.1"


def generate(root: Path = ROOT, build_number: str = "1") -> Path:
    if not build_number.isdecimal() or int(build_number) < 1:
        raise ValueError("Build number must be a positive integer.")
    config = json.loads((root / ".ci/app_config.json").read_text())
    generated = root / "build/native"
    generated.mkdir(parents=True, exist_ok=True)
    assets = generated / "Brand.xcassets"
    wordmark = assets / "BrandWordmark.imageset"
    wordmark.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / "assets/brand/source/wordmark.jpg", wordmark / "wordmark.jpg")
    (wordmark / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "filename": "wordmark.jpg"}],
        "info": {"author": "xcode", "version": 1},
    }))
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    info = {
        "CFBundleDevelopmentRegion": "ja", "CFBundleLocalizations": ["ja"],
        "CFBundleDisplayName": "GiriStair", "CFBundleName": "GiriStair",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION, "CFBundleVersion": build_number,
        "LSRequiresIPhoneOS": True, "UILaunchStoryboardName": "LaunchScreen",
        "UIApplicationSupportsIndirectInputEvents": True,
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
        "ITSAppUsesNonExemptEncryption": False,
        "NSPhotoLibraryUsageDescription": "参加者の文字読み取り、お題・プレイヤーのアイコン・共有画像に写真を使用します。",
        "NSPhotoLibraryAddUsageDescription": "作成した共有画像を写真ライブラリへ保存します。",
        "NSCameraUsageDescription": "参加者一覧や画像お題を読み取るためにカメラを使用します。",
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
        "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    }
    with (generated / "Info.plist").open("wb") as output:
        plistlib.dump(info, output)
    project = {
        "name": "GiriStair",
        "options": {"bundleIdPrefix": "com.livestair", "developmentLanguage": "ja", "deploymentTarget": {"iOS": MINIMUM_IOS}},
        "settings": {"base": {"SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": MINIMUM_IOS}},
        "targets": {"GiriStair": {
            "type": "application", "platform": "iOS",
            "sources": [
                {"path": "GiriStair"},
                {"path": "../ios/Runner/Assets.xcassets", "buildPhase": "resources"},
                {"path": "../ios/Runner/Base.lproj/LaunchScreen.storyboard", "buildPhase": "resources"},
                {"path": "../build/native/Brand.xcassets", "buildPhase": "resources"},
            ],
            "settings": {"base": {
                "INFOPLIST_FILE": "../build/native/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
                "PRODUCT_BUNDLE_IDENTIFIER": config["bundle_id"],
                "PRODUCT_NAME": "GiriStair", "MARKETING_VERSION": VERSION,
                "CURRENT_PROJECT_VERSION": build_number, "TARGETED_DEVICE_FAMILY": "1,2",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_STYLE": "Automatic", "SWIFT_EMIT_LOC_STRINGS": "YES",
            }},
        }},
        "schemes": {"GiriStair": {"build": {"targets": {"GiriStair": "all"}}, "run": {"config": "Debug"}, "archive": {"config": "Release"}}},
    }
    path = root / "native/project.json"
    path.write_text(json.dumps(project, indent=2) + "\n")
    return path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-number", default="1")
    args = parser.parse_args()
    print(generate(build_number=args.build_number))
