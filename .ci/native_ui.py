#!/usr/bin/env python3
"""Run the native navigation regression on one available iPhone, without captures."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import time


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
    selectors = os.environ.get("GIRI_UI_TESTS", "GiriStairUITests").split(",")
    allowance = os.environ.get("GIRI_UI_ALLOWANCE", "240")
    command = ["xcodebuild", "-project", "native/GiriStair.xcodeproj", "-scheme", "GiriStair",
               "-configuration", "Debug", "-destination", "id=" + device["udid"],
               "-derivedDataPath", "build/native/DerivedData", "-parallel-testing-enabled", "NO",
               "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", allowance,
               "-maximum-test-execution-time-allowance", "300",
               *["-only-testing:" + selector for selector in selectors], "CODE_SIGNING_ALLOWED=NO", "test"]
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True, text=True, encoding="utf-8", errors="replace")

        action = {"time": time.monotonic(), "label": "", "sampled": False, "case": 0}

        def sample_stalled_application():
            while process.poll() is None:
                time.sleep(2)
                if not action["label"] or action["sampled"] or time.monotonic() - action["time"] < 35:
                    continue
                action["sampled"] = True
                try:
                    pids = subprocess.check_output(["pgrep", "-x", "GiriStair"], text=True).split()
                    for pid in pids:
                        path = log.parent / ("hang-" + str(action["case"]) + "-" + pid + ".txt")
                        subprocess.run(["sample", pid, "1", "10", "-mayDie", "-file", str(path)],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45, check=True)
                        print("Native hang sample after " + action["label"] + ": " + str(path), flush=True)
                except (subprocess.SubprocessError, OSError) as error:
                    print("Native hang sample unavailable: " + str(error), flush=True)

        def forward_output():
            for line in process.stdout:
                output.write(line)
                output.flush()
                if "Test Case" in line and "started" in line:
                    action.update(time=time.monotonic(), label="", sampled=False, case=action["case"] + 1)
                if "Tap " in line:
                    action.update(time=time.monotonic(), label=line.strip())
                if any(marker in line for marker in ("Test Case", "Test Suite", "Tap ", "error:", "failed", "TEST SUCCEEDED", "TEST FAILED")):
                    print(line.rstrip(), flush=True)

        reader = threading.Thread(target=forward_output, daemon=True)
        reader.start()
        sampler = threading.Thread(target=sample_stalled_application, daemon=True)
        sampler.start()
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
        reader.join(timeout=10)
    for path in sorted(log.parent.glob("hang-*.txt")):
        print("Native main-thread sample: " + path.name)
        sample = path.read_text(errors="replace").splitlines()
        start = next((i for i, line in enumerate(sample) if "DispatchQueue" in line and "main" in line), 0)
        print("\n".join(sample[start:start + 220]))
    print("\n".join(log.read_text(errors="replace").splitlines()[-160:]))
    raise SystemExit(returncode)


if __name__ == "__main__":
    main()
