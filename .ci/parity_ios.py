#!/usr/bin/env python3
"""Build-host helpers for actual iOS simulator screenshots, not mock renders."""

from __future__ import annotations

import argparse
import hashlib
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys
import time


def version(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value))


def select_xcode() -> None:
    candidates = []
    for application in Path("/Applications").glob("Xcode*.app"):
        info = application / "Contents/Info.plist"
        if not info.is_file():
            continue
        with info.open("rb") as source:
            release = plistlib.load(source).get("CFBundleShortVersionString", "0")
        parsed = version(release)
        if parsed and parsed[0] >= 26:
            candidates.append((parsed, str(application / "Contents/Developer")))
    if not candidates:
        raise RuntimeError(
            "No installed Xcode 26 or newer. Native Liquid Glass verification "
            "requires linking the iOS 26 SDK; an older SDK is not equivalent."
        )
    _, developer = max(candidates)
    subprocess.run(["sudo", "xcode-select", "--switch", developer], check=True)
    subprocess.run(["xcodebuild", "-version"], check=True)
    subprocess.run(["xcodebuild", "-showsdks"], check=True)


def choose_phone(devices: dict) -> tuple[str, dict]:
    candidates = []
    preferred = {"iPhone 16": 0, "iPhone 17": 1, "iPhone 16 Pro": 2}
    for runtime, entries in devices.get("devices", {}).items():
        match = re.search(r"SimRuntime\.iOS-(\d+(?:-\d+)*)$", runtime)
        if not match:
            continue
        release = version(match.group(1))
        if not release or release[0] < 26:
            continue
        for device in entries:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                key = (
                    tuple(-part for part in release),
                    preferred.get(device["name"], 10),
                    device["name"],
                )
                candidates.append((key, runtime, device))
    if not candidates:
        raise RuntimeError(
            "No available iPhone on an iOS 26+ simulator runtime. "
            "An older runtime cannot validate the current native tab appearance."
        )
    _, runtime, device = min(candidates, key=lambda item: item[0])
    return runtime, device


def run(*arguments: str, timeout: int = 180) -> subprocess.CompletedProcess:
    print(f"$ {shlex.join(arguments)} (timeout {timeout}s)", flush=True)
    try:
        return subprocess.run(
            list(arguments), check=True, capture_output=True, text=True, timeout=timeout
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        # TimeoutExpired may retain bytes even with text=True. Preserve the
        # simulator's boot progress instead of losing it behind a traceback.
        for stream in (error.stdout, error.stderr):
            if stream:
                text = stream.decode("utf-8", errors="replace") if isinstance(stream, bytes) else stream
                print(text, file=sys.stderr, flush=True)
        raise


def available_phone(output: Path, listing_name: str) -> tuple[str, dict]:
    output.mkdir(parents=True, exist_ok=True)
    listing = run("xcrun", "simctl", "list", "devices", "available", "--json").stdout
    (output / listing_name).write_text(listing, encoding="utf-8")
    return choose_phone(json.loads(listing))


def start_phone(device: dict) -> None:
    # An earlier prepare step can leave the device booting; booting it a second
    # time is an error rather than a useful way to wait for readiness.
    if device.get("state") not in {"Booted", "Booting"}:
        run("xcrun", "simctl", "boot", device["udid"])


def prepare_simulator(output: Path) -> None:
    runtime, device = available_phone(output, "available-devices-before-build.json")
    start_phone(device)
    print(f"Started {device['name']} ({runtime}); boot overlaps the app build.", flush=True)


def verify_font_diagnostics(logs: str) -> dict:
    if re.search(r"CoreText note:.*TimesNewRoman", logs):
        raise RuntimeError("CoreText substituted Times New Roman for a system UI font.")
    marker = "GiriStairTypography "
    fonts = {}
    for line in logs.splitlines():
        if marker not in line:
            continue
        entry, _ = json.JSONDecoder().raw_decode(line.split(marker, 1)[1])
        fonts.update(entry)
    if fonts:
        for role in ("pageTitle", "sectionTitle", "formLabel", "input", "dateValue"):
            family = fonts.get(role, {}).get("japaneseFamilyName", "")
            if not family or re.search(r"Mincho|Times|Serif", family, re.IGNORECASE):
                raise RuntimeError(f"Unexpected Japanese UI font for {role}: {family!r}")
        return fonts
    raise RuntimeError("No native font diagnostics were captured; glyph selection is unverified.")


def capture(app: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with (app / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    bundle_id = info["CFBundleIdentifier"]
    runtime, device = available_phone(output, "available-devices.json")
    udid = device["udid"]
    start_phone(device)
    run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=600)
    run("xcrun", "simctl", "spawn", udid, "defaults", "write", ".GlobalPreferences",
        "AppleLanguages", "-array", "ja", "en")
    run("xcrun", "simctl", "spawn", udid, "defaults", "write", ".GlobalPreferences",
        "AppleLocale", "-string", "ja_JP")
    run("xcrun", "simctl", "ui", udid, "appearance", "light")
    run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--batteryState", "charged", "--batteryLevel", "100")
    run("xcrun", "simctl", "install", udid, str(app.resolve()))
    captures = []
    for screen in ("registration", "detail", "calendar", "thinking", "venue"):
        launch = run(
            "xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle_id,
            "--disable-vm-service", "--disable-vm-service-publication",
            "--stair-font-diagnostics", f"--stair-preview-screen={screen}",
        )
        # Resolve the real app's fonts, native tab/back items and map before
        # capturing the composed simulator window. The harness has no user data.
        time.sleep(15)
        screenshot = output / f"{screen}-iphone-ja.png"
        run("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(screenshot))
        captures.append({"screen": screen, "screenshot": screenshot.name, "launch": launch.stdout})
    xcode = run("xcodebuild", "-version").stdout
    metadata = {
        "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
        "device": device["name"],
        "runtime": runtime,
        "udid": udid,
        "xcode": xcode,
        "bundleId": bundle_id,
        "locale": "ja_JP",
        "appearance": "light",
        "entrypoint": "tool/parity_preview.dart",
        "initialTab": 0,
        "store": "in-memory synthetic event only; no user data",
        "dateNote": "The blank registration date uses the real app's current local date.",
        "captures": captures,
    }
    (output / "metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    logs = run(
        "xcrun", "simctl", "spawn", udid, "log", "show", "--last", "5m",
        "--style", "compact", "--predicate", 'process == "Runner"',
    ).stdout
    (output / "simulator.log").write_text(logs, encoding="utf-8")
    requested = {item["screen"] for item in captures}
    confirmed = set(re.findall(r"GiriStairPreview (\w+)", logs))
    if not requested.issubset(confirmed):
        raise RuntimeError(f"Preview routes were not confirmed: {sorted(requested - confirmed)}")
    hashes = {
        hashlib.sha256((output / item["screenshot"]).read_bytes()).hexdigest()
        for item in captures
    }
    if len(hashes) != len(captures):
        raise RuntimeError("Preview routes produced identical screenshots; inspect the route setup.")
    fonts = verify_font_diagnostics(logs)
    (output / "font-metadata.json").write_text(
        json.dumps(fonts, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("select-xcode")
    prepare = commands.add_parser("prepare-simulator")
    prepare.add_argument("--output", type=Path, required=True)
    screenshot = commands.add_parser("capture")
    screenshot.add_argument("--app", type=Path, required=True)
    screenshot.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.command == "select-xcode":
        select_xcode()
    elif arguments.command == "prepare-simulator":
        prepare_simulator(arguments.output)
    else:
        capture(arguments.app, arguments.output)


if __name__ == "__main__":
    main()
