#!/usr/bin/env python3
"""Generate the independent SwiftUI iPhone project without Flutter tooling."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from xml.parsers.expat import ExpatError

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.36"
MINIMUM_IOS = "18.1"
SYNC_INFO_KEY = "AccountSyncCloudContainer"
CONTAINER_ENTITLEMENT = "com.apple.developer.icloud-container-identifiers"
SERVICES_ENTITLEMENT = "com.apple.developer.icloud-services"
ENVIRONMENT_ENTITLEMENT = "com.apple.developer.icloud-container-environment"


def generate(root: Path = ROOT, build_number: str = "1", account_sync_cloudkit: bool = False) -> Path:
    if not build_number.isdecimal() or int(build_number) < 1:
        raise ValueError("Build number must be a positive integer.")
    config = json.loads((root / ".ci/app_config.json").read_text())
    generated = root / "build/native"
    generated.mkdir(parents=True, exist_ok=True)
    assets = generated / "Brand.xcassets"
    wordmark = assets / "BrandWordmark.imageset"
    wordmark.mkdir(parents=True, exist_ok=True)
    transparent_wordmark = root / "assets/brand/derived/wordmark-transparent.png"
    source_wordmark = transparent_wordmark if transparent_wordmark.exists() else root / "assets/brand/source/wordmark.jpg"
    wordmark_name = "wordmark" + source_wordmark.suffix
    shutil.copyfile(source_wordmark, wordmark / wordmark_name)
    (wordmark / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "filename": wordmark_name}],
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
        "NSCalendarsWriteOnlyAccessUsageDescription": "大喜利会の予定をiPhoneのカレンダーに書き出します。",
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
        "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    }
    entitlements_path = generated / "AccountSync.entitlements"
    if account_sync_cloudkit:
        container = f"iCloud.{config['bundle_id']}"
        info[SYNC_INFO_KEY] = container
        with entitlements_path.open("wb") as output:
            plistlib.dump({
                CONTAINER_ENTITLEMENT: [container],
                SERVICES_ENTITLEMENT: ["CloudKit"],
            }, output)
    else:
        entitlements_path.unlink(missing_ok=True)
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
        }, "GiriStairUITests": {
            "type": "bundle.ui-testing", "platform": "iOS",
            "sources": [{"path": "UITests"}],
            "dependencies": [{"target": "GiriStair"}],
            "settings": {"base": {
                "PRODUCT_BUNDLE_IDENTIFIER": config["bundle_id"] + ".uitests",
                "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "GiriStair",
                "CODE_SIGNING_ALLOWED": "NO",
            }},
        }},
        "schemes": {"GiriStair": {
            "build": {"targets": {"GiriStair": "all", "GiriStairUITests": ["test"]}},
            "run": {"config": "Debug"}, "archive": {"config": "Release"},
            "test": {"config": "Debug", "targets": [{"name": "GiriStairUITests", "parallelizable": False}]},
        }},
    }
    if account_sync_cloudkit:
        project["targets"]["GiriStair"]["settings"]["base"]["CODE_SIGN_ENTITLEMENTS"] = "../build/native/AccountSync.entitlements"
    path = root / "native/project.json"
    path.write_text(json.dumps(project, indent=2) + "\n")
    return path


def verify_account_sync_ipa(ipa_dir: Path, bundle_id: str, version: str, build_number: str) -> None:
    ipas = sorted(ipa_dir.glob("*.ipa"))
    if len(ipas) != 1:
        raise ValueError(f"iCloud同期の確認にはIPAが1件必要です。{ipa_dir} に {len(ipas)} 件あります。")

    container = f"iCloud.{bundle_id}"
    with tempfile.TemporaryDirectory(prefix="giristair-verify-ipa-") as directory:
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(ipas[0]), directory], check=True)
        apps = sorted((Path(directory) / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("IPAのPayloadに確認対象のアプリが1件必要です。")
        app = apps[0]
        info = read_ipa_plist((app / "Info.plist").read_bytes(), "Info.plist")
        expected_info = {
            "CFBundleIdentifier": bundle_id,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build_number,
            SYNC_INFO_KEY: container,
        }
        for key, value in expected_info.items():
            if info.get(key) != value:
                raise ValueError(f"IPAのInfo.plistで {key} が一致しません。期待値 {value!r}、実際 {info.get(key)!r}。")

        signature = subprocess.run(
            ["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", str(app)],
            check=True, stdout=subprocess.PIPE,
        )
        entitlements = read_ipa_plist(signature.stdout, "署名のentitlements")
        containers = entitlements.get(CONTAINER_ENTITLEMENT)
        if not isinstance(containers, list) or container not in containers:
            raise ValueError(f"IPAの署名にiCloudコンテナ {container} がありません。Codemagicの署名プロファイルを確認してください。")
        services = entitlements.get(SERVICES_ENTITLEMENT)
        if not isinstance(services, list) or "CloudKit" not in services:
            raise ValueError("IPAの署名にCloudKitの権限がありません。Codemagicの署名プロファイルを確認してください。")
        if entitlements.get(ENVIRONMENT_ENTITLEMENT, "Production") != "Production":
            raise ValueError("TestFlight用IPAのCloudKit環境にはProductionが必要です。")

    print(f"GiriStair {version} ({build_number}) のIPAでiCloud同期が有効です。コンテナ {container}")


def read_ipa_plist(data: bytes, description: str) -> dict:
    try:
        values = plistlib.loads(data)
    except (ValueError, ExpatError) as error:
        raise ValueError(f"IPAの{description}を読み込めません。") from error
    if not isinstance(values, dict):
        raise ValueError(f"IPAの{description}の形式を確認できません。")
    return values


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-number", default="1")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--account-sync-cloudkit", action="store_true")
    action.add_argument("--verify-account-sync-ipa", type=Path, metavar="IPA_DIRECTORY")
    args = parser.parse_args()
    if args.verify_account_sync_ipa is not None:
        config = json.loads((ROOT / ".ci/app_config.json").read_text())
        try:
            verify_account_sync_ipa(args.verify_account_sync_ipa, config["bundle_id"], VERSION, args.build_number)
        except (subprocess.CalledProcessError, ValueError, OSError) as error:
            parser.exit(1, f"iCloud同期のIPA確認に失敗しました。{error}\n")
    else:
        print(generate(build_number=args.build_number, account_sync_cloudkit=args.account_sync_cloudkit))
