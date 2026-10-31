#!/usr/bin/env python3
"""Run the native navigation regression on one available iPhone, without captures."""
import json
import os
from pathlib import Path
import re
import signal
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
        subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True, timeout=120)
    subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True, timeout=180)
    log = Path("build/native/uitest.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    command = ["xcodebuild", "-project", "native/GiriStair.xcodeproj", "-scheme", "GiriStair",
               "-configuration", "Debug", "-destination", "id=" + device["udid"],
               "-derivedDataPath", "build/native/DerivedData", "-parallel-testing-enabled", "NO",
               "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "180",
               "-maximum-test-execution-time-allowance", "240",
               "-only-testing:GiriStairUITests", "CODE_SIGNING_ALLOWED=NO", "test"]
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            returncode = process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            print("Native UI regression exceeded 15 minutes; preserving failure log.")
            returncode = 1
    print("\n".join(log.read_text(errors="replace").splitlines()[-160:]))
    raise SystemExit(returncode)


if __name__ == "__main__":
    main()
