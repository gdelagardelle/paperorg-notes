#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator, newest runtime first.

CI picks a device at run time rather than naming one. project.yml declares
deploymentTarget iOS 17.0, so any iPhone the runner offers will do, and
hardcoding a name breaks silently the day the runner image drops it.
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

    # Sorting the runtime identifiers in reverse puts the newest iOS first,
    # which is what we want to build against.
    for runtime in sorted(devices, reverse=True):
        if "iOS" not in runtime:
            continue
        for device in devices[runtime]:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                print(device["udid"])
                return

    sys.exit("no available iPhone simulator on this runner")


if __name__ == "__main__":
    main()
