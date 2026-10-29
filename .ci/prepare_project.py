#!/usr/bin/env python3
"""Create missing native runners without replacing application source files."""

from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from brand_assets import apply_brand_assets


ROOT = Path(__file__).resolve().parents[1]


def version_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


def set_ios_settings(root: Path, config: dict[str, str]) -> None:
    project = root / "ios/Runner.xcodeproj/project.pbxproj"
    project_text = project.read_text(encoding="utf-8")
    identifiers = re.findall(
        r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^;"\s]+)"?\s*;', project_text
    )
    bundle_id = config["bundle_id"]
    if bundle_id not in identifiers:
        raise ValueError(
            f"iOSのBundle IDが{bundle_id}と一致しません。"
            "Apple登録値とアプリ設定をAIに確認するよう依頼してください。"
        )
    minimum_ios = config["minimum_ios"]

    def deployment_target(match: re.Match[str]) -> str:
        target = match.group(1)
        if version_tuple(target) < version_tuple(minimum_ios):
            target = minimum_ios
        return f"IPHONEOS_DEPLOYMENT_TARGET = {target};"

    project_text = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([0-9.]+)\s*;",
        deployment_target,
        project_text,
    )
    project.write_text(project_text, encoding="utf-8")

    info_path = root / "ios/Runner/Info.plist"
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleDisplayName"] = config["display_name"]
    info["CFBundleName"] = config["display_name"]
    # Flutter's Locale('ja') does not declare the native app's localization.
    # Keep generated runners, system dialogs and app language selection Japanese.
    info["CFBundleDevelopmentRegion"] = "ja"
    info["CFBundleLocalizations"] = ["ja"]
    # Initial app stores on-device records and adds no encryption features.
    info["ITSAppUsesNonExemptEncryption"] = False
    with info_path.open("wb") as destination:
        plistlib.dump(info, destination, sort_keys=False)

    framework_info_path = root / "ios/Flutter/AppFrameworkInfo.plist"
    if framework_info_path.exists():
        with framework_info_path.open("rb") as source:
            framework_info = plistlib.load(source)
        old_minimum = framework_info.get("MinimumOSVersion", "0.0")
        if version_tuple(old_minimum) < version_tuple(minimum_ios):
            framework_info["MinimumOSVersion"] = minimum_ios
            with framework_info_path.open("wb") as destination:
                plistlib.dump(framework_info, destination, sort_keys=False)

    podfile_path = root / "ios/Podfile"
    if podfile_path.exists():
        podfile = podfile_path.read_text(encoding="utf-8")
        platform = re.compile(
            r"^\s*#?\s*platform\s+:ios,\s*['\"]([0-9.]+)['\"]\s*$",
            re.MULTILINE,
        )
        match = platform.search(podfile)
        if match is not None:
            current = match.group(1)
            target = current if version_tuple(current) > version_tuple(minimum_ios) else minimum_ios
            podfile = platform.sub(f"platform :ios, '{target}'", podfile)
        else:
            podfile = f"platform :ios, '{minimum_ios}'\n{podfile}"
        podfile_path.write_text(podfile, encoding="utf-8")


def set_android_settings(root: Path, config: dict[str, str]) -> None:
    gradle_candidates = [
        root / "android/app/build.gradle.kts",
        root / "android/app/build.gradle",
    ]
    gradle_path = next((path for path in gradle_candidates if path.exists()), None)
    if gradle_path is None:
        raise ValueError("Androidのapp/build.gradleが見つかりません。")
    gradle = gradle_path.read_text(encoding="utf-8")
    for setting in ("applicationId", "namespace"):
        match = re.search(rf"\b{setting}\s*(?:=\s*)?['\"]([^'\"]+)['\"]", gradle)
        if match is None or match.group(1) != config["bundle_id"]:
            raise ValueError(f"Androidの{setting}が{config['bundle_id']}と一致しません。")
    manifest_path = root / "android/app/src/main/AndroidManifest.xml"
    manifest = manifest_path.read_text(encoding="utf-8")
    manifest = re.sub(
        r'android:label="[^"]*"',
        f'android:label="{config["display_name"]}"',
        manifest,
        count=1,
    )
    parsed = ET.fromstring(manifest)
    application = parsed.find("application")
    android_label = "{http://schemas.android.com/apk/res/android}label"
    if application is None or application.get(android_label) != config["display_name"]:
        raise ValueError("Androidのアプリ表示名を設定できませんでした。")
    manifest_path.write_text(manifest, encoding="utf-8")


def prepare(root: Path = ROOT) -> None:
    config = json.loads((root / ".ci/app_config.json").read_text(encoding="utf-8"))
    expected_bundle = os.environ.get("BUNDLE_ID")
    if expected_bundle and expected_bundle != config["bundle_id"]:
        raise ValueError("Codemagicと.ci/app_config.jsonのBundle IDが一致しません。")
    if config["bundle_id"] != f"{config['organization']}.{config['project_name']}":
        raise ValueError("初期プロジェクトのorganization/project_nameとBundle IDが一致しません。")
    missing = [name for name in ("ios", "android") if not (root / name).exists()]
    if missing:
        with tempfile.TemporaryDirectory(prefix="giristair-native-") as directory:
            generated = Path(directory) / config["project_name"]
            subprocess.run(
                [
                    "flutter", "create", "--no-pub",
                    f"--platforms={','.join(missing)}",
                    f"--org={config['organization']}",
                    f"--project-name={config['project_name']}",
                    str(generated),
                ],
                check=True,
            )
            for platform in missing:
                shutil.copytree(generated / platform, root / platform)
    set_ios_settings(root, config)
    set_android_settings(root, config)
    apply_brand_assets(root)
    print(f"GiriStairのiOS/Android設定を準備しました: {config['bundle_id']}")


if __name__ == "__main__":
    try:
        prepare()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"プロジェクトの準備に失敗しました: {error}") from error
