#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator, newest runtime first.

CI picks a device at run time rather than naming one. project.yml declares
deploymentTarget iOS 17.0. Exclude runtimes with the StoreKit Test regression;
hardcoding a device name breaks when the runner image drops it.
"""

from __future__ import annotations

import json
import subprocess
import sys


def main() -> None:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    devices = json.loads(raw)["devices"]

    # iOS 26.4/26.5 have a StoreKit Test configuration regression (FB22237318).
    # Do not turn missing test purchases into skips or false product failures.
    # Use a working installed runtime; numeric ordering also handles 26.10.
    def version(runtime: str) -> tuple[int, ...]:
        return tuple(int(part) for part in runtime.split("iOS-")[-1].split("-"))

    ios_runtimes = [runtime for runtime in devices if "iOS-" in runtime]
    for runtime in sorted(ios_runtimes, key=version, reverse=True):
        if version(runtime)[:2] in [(26, 4), (26, 5)]:
            continue
        for device in devices[runtime]:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                print(device["udid"])
                return

    sys.exit("no iPhone simulator with a working StoreKit Test runtime on this runner")


if __name__ == "__main__":
    main()
