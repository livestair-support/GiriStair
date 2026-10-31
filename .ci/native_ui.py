#!/usr/bin/env python3
"""Run the native navigation regression on one available iPhone, without captures."""
import json
from pathlib import Path
import re
import subprocess


def main():
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    runtimes = sorted(data["devices"], key=lambda x: tuple(map(int, re.findall(r"\d+", x))), reverse=True)
    device = next((d for runtime in runtimes if "iOS" in runtime for d in data["devices"][runtime]
                   if d.get("isAvailable") and d["name"].startswith("iPhone")), None)
    if device is None:
        raise RuntimeError("No available iPhone simulator for native UI regression")
    print("Native UI regression simulator:", device["name"], device["udid"], flush=True)
    if device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True)
    log = Path("build/native/uitest.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    command = ["xcodebuild", "-project", "native/GiriStair.xcodeproj", "-scheme", "GiriStair",
               "-configuration", "Debug", "-destination", "id=" + device["udid"],
               "-derivedDataPath", "build/native/DerivedData", "-parallel-testing-enabled", "NO",
               "-only-testing:GiriStairUITests", "CODE_SIGNING_ALLOWED=NO", "test"]
    with log.open("w") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
    print("\n".join(log.read_text(errors="replace").splitlines()[-160:]))
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
