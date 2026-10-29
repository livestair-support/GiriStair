#!/usr/bin/env python3
"""Adopt the supplied brand artwork and restore it after native bootstrapping.

Normal preparation uses only the Python standard library. Pillow is needed only
for --regenerate, which resizes original pixels and adds OS-required safe padding.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BRAND = Path("assets/brand")
BACKGROUND = (245, 241, 232)
BACKGROUND_HEX = "#F5F1E8"


def apply_brand_assets(root: Path = ROOT) -> bool:
    package = root / BRAND / "native-assets.zip"
    if not package.is_file():
        return False
    with zipfile.ZipFile(package) as archive:
        for entry in archive.infolist():
            relative = Path(entry.filename)
            allowed = entry.filename.startswith((
                "ios/Runner/Assets.xcassets/",
                "ios/Runner/Base.lproj/LaunchScreen.storyboard",
                "android/app/src/main/res/",
            ))
            if not allowed or relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Unexpected path in brand asset package.")
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))
    manifest_path = root / "android/app/src/main/AndroidManifest.xml"
    if manifest_path.is_file():
        manifest = manifest_path.read_text(encoding="utf-8")
        manifest = re.sub(
            r'android:theme="@style/(?:LaunchTheme|BrandLaunchTheme)"',
            'android:theme="@style/BrandLaunchTheme"', manifest, count=1,
        )
        match = re.search(r"<application\b[^>]*>", manifest)
        if match and "android:roundIcon=" not in match.group():
            tag = match.group()
            tag = tag[:-1] + '\n        android:roundIcon="@mipmap/ic_launcher_round">'
            manifest = manifest[:match.start()] + tag + manifest[match.end():]
        manifest_path.write_text(manifest, encoding="utf-8")
    return True


def check_brand_assets(root: Path = ROOT) -> None:
    manifest = json.loads((root / BRAND / "manifest.json").read_text())
    for relative, digest in manifest["sources"].items():
        if hashlib.sha256((root / relative).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Brand original changed: {relative}")
    with zipfile.ZipFile(root / BRAND / "native-assets.zip") as archive:
        for relative, digest in manifest["native"].items():
            packed = archive.read(relative)
            if hashlib.sha256(packed).hexdigest() != digest:
                raise ValueError(f"Brand package changed: {relative}")
            if (root / relative).read_bytes() != packed:
                raise ValueError(f"Native brand assets need preparation: {relative}")


def regenerate(root: Path = ROOT) -> None:
    from PIL import Image, ImageChops, ImageDraw, ImageOps

    source = root / BRAND / "source"
    icon = ImageOps.exif_transpose(Image.open(source / "app_icon.jpg")).convert("RGB")
    launch = ImageOps.exif_transpose(Image.open(source / "launch_screen.jpg")).convert("RGB")
    files: dict[str, bytes] = {}

    def text(path: str, value: str) -> None:
        files[path] = value.encode("utf-8")

    def picture(path: str, value: Image.Image) -> None:
        output = io.BytesIO()
        value.save(output, format="PNG", optimize=True)
        files[path] = output.getvalue()

    def fit(value: Image.Image, size: tuple[int, int]) -> Image.Image:
        fitted = ImageOps.contain(value, size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", size, BACKGROUND)
        canvas.paste(fitted, ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2))
        return canvas

    entries = []
    specifications = [
        ("iphone", "20", 2), ("iphone", "20", 3),
        ("iphone", "29", 1), ("iphone", "29", 2), ("iphone", "29", 3),
        ("iphone", "40", 2), ("iphone", "40", 3),
        ("iphone", "60", 2), ("iphone", "60", 3),
        ("ipad", "20", 1), ("ipad", "20", 2),
        ("ipad", "29", 1), ("ipad", "29", 2),
        ("ipad", "40", 1), ("ipad", "40", 2),
        ("ipad", "76", 1), ("ipad", "76", 2), ("ipad", "83.5", 2),
        ("ios-marketing", "1024", 1),
    ]
    for idiom, points, scale in specifications:
        filename = f"Icon-App-{points}x{points}@{scale}x.png"
        entries.append({
            "idiom": idiom, "size": f"{points}x{points}",
            "scale": f"{scale}x", "filename": filename,
        })
        pixels = int(float(points) * scale)
        picture("ios/Runner/Assets.xcassets/AppIcon.appiconset/" + filename,
                icon.resize((pixels, pixels), Image.Resampling.LANCZOS))
    text("ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json",
         json.dumps({"images": entries, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    images = []
    for scale in (1, 2, 3):
        filename = "LaunchImage.png" if scale == 1 else f"LaunchImage@{scale}x.png"
        picture("ios/Runner/Assets.xcassets/LaunchImage.imageset/" + filename,
                fit(launch, (393 * scale, 852 * scale)))
        images.append({"idiom": "universal", "scale": f"{scale}x", "filename": filename})
    text("ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json",
         json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    text("ios/Runner/Base.lproj/LaunchScreen.storyboard", """<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="12121" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" colorMatched="YES" initialViewController="brand-launch">
    <dependencies><deployment identifier="iOS"/><plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="12089"/></dependencies>
    <scenes><scene sceneID="brand-scene"><objects>
        <viewController id="brand-launch" sceneMemberID="viewController">
            <view key="view" contentMode="scaleToFill" id="brand-view">
                <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                <subviews><imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleAspectFit" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="brand-image"/></subviews>
                <color key="backgroundColor" red="0.9607843137" green="0.9450980392" blue="0.9098039216" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                <constraints>
                    <constraint firstItem="brand-image" firstAttribute="leading" secondItem="brand-view" secondAttribute="leading" id="brand-leading"/>
                    <constraint firstAttribute="trailing" secondItem="brand-image" secondAttribute="trailing" id="brand-trailing"/>
                    <constraint firstItem="brand-image" firstAttribute="top" secondItem="brand-view" secondAttribute="top" id="brand-top"/>
                    <constraint firstAttribute="bottom" secondItem="brand-image" secondAttribute="bottom" id="brand-bottom"/>
                </constraints>
            </view>
        </viewController>
        <placeholder placeholderIdentifier="IBFirstResponder" id="brand-first-responder" sceneMemberID="firstResponder"/>
    </objects></scene></scenes>
    <resources><image name="LaunchImage" width="393" height="852"/></resources>
</document>
""")

    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        picture(f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
                icon.resize((size, size), Image.Resampling.LANCZOS))
        rounded = Image.new("RGBA", (size, size))
        ImageDraw.Draw(rounded).ellipse((0, 0, size - 1, size - 1), fill=BACKGROUND + (255,))
        safe = round(size * 2 / 3)
        rounded.paste(icon.resize((safe, safe), Image.Resampling.LANCZOS),
                      ((size - safe) // 2, (size - safe) // 2))
        picture(f"android/app/src/main/res/mipmap-{density}/ic_launcher_round.png", rounded)
    foreground = Image.new("RGBA", (432, 432))
    # Keep even the bottom wordmark inside Android's 66dp circular safe zone.
    foreground.paste(icon.resize((216, 216), Image.Resampling.LANCZOS), (108, 108))
    picture("android/app/src/main/res/drawable-nodpi/brand_icon_foreground.png", foreground)
    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/brand_background"/>
    <foreground android:drawable="@drawable/brand_icon_foreground"/>
</adaptive-icon>
"""
    for filename in ("ic_launcher.xml", "ic_launcher_round.xml"):
        text("android/app/src/main/res/mipmap-anydpi-v26/" + filename, adaptive)

    # Crop only the empty surround from the supplied launch screen for Android's
    # fixed-size native splash drawable; all lettering pixels are retained.
    difference = ImageChops.difference(launch, Image.new("RGB", launch.size, BACKGROUND))
    bounds = difference.convert("L").point(lambda value: 255 if value > 20 else 0).getbbox()
    if bounds is None:
        raise ValueError("The launch artwork contains no visible wordmark.")
    left, top, right, bottom = bounds
    wordmark = launch.crop((max(0, left - 16), max(0, top - 16),
                           min(launch.width, right + 16), min(launch.height, bottom + 16)))
    picture("android/app/src/main/res/drawable-nodpi/brand_launch_logo.png", wordmark)
    splash = Image.new("RGBA", (864, 864))
    small = ImageOps.contain(wordmark, (540, 540), Image.Resampling.LANCZOS)
    splash.paste(small, ((864 - small.width) // 2, (864 - small.height) // 2))
    picture("android/app/src/main/res/drawable-nodpi/brand_splash_icon.png", splash)
    height = 244 * wordmark.height / wordmark.width
    background = f"""<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/brand_background"/>
    <item android:gravity="center" android:width="244dp" android:height="{height:.2f}dp">
        <bitmap android:gravity="fill" android:src="@drawable/brand_launch_logo"/>
    </item>
</layer-list>
"""
    for name in ("drawable/brand_launch_background.xml", "drawable/launch_background.xml", "drawable-v21/launch_background.xml"):
        text("android/app/src/main/res/" + name, background)
    text("android/app/src/main/res/values/brand_colors.xml",
         f'<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="brand_background">{BACKGROUND_HEX}</color></resources>\n')
    for api, extra in (
        ("values", ""),
        ("values-v29", '        <item name="android:forceDarkAllowed">false</item>\n'),
        ("values-v31", """        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowSplashScreenBackground">@color/brand_background</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/brand_splash_icon</item>
        <item name="android:windowSplashScreenIconBackgroundColor">@color/brand_background</item>
"""),
    ):
        text(f"android/app/src/main/res/{api}/brand_launch.xml", """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="BrandLaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/brand_launch_background</item>
        <item name="android:windowLightStatusBar">true</item>
""" + extra + """    </style>
</resources>
""")
    package = root / BRAND / "native-assets.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path, data in sorted(files.items()):
            entry = zipfile.ZipInfo(path, date_time=(2026, 10, 29, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    metadata = {
        "sources": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in sorted(source.glob("*.jpg"))},
        "native": {path: hashlib.sha256(data).hexdigest() for path, data in sorted(files.items())},
        "background": BACKGROUND_HEX,
        "launchWordmarkCrop": [max(0, left - 16), max(0, top - 16),
                               min(launch.width, right + 16), min(launch.height, bottom + 16)],
    }
    (root / BRAND / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    apply_brand_assets(root)
    check_brand_assets(root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regenerate", action="store_true")
    arguments = parser.parse_args()
    if arguments.regenerate:
        regenerate()
    else:
        check_brand_assets()
    print("Brand artwork and native assets verified.")
