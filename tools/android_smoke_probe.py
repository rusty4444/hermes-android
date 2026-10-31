#!/usr/bin/env python3
"""Text-first UI probe for the disposable Android smoke emulator only."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ADB = str(Path.home() / "Library/Android/sdk/platform-tools/adb")
SERIAL = "emulator-5580"


def adb(*args):
    return subprocess.check_output([ADB, "-s", SERIAL, *args], text=True)


def nodes():
    raw = adb("exec-out", "uiautomator", "dump", "/dev/tty")
    start, end = raw.find("<?xml"), raw.rfind("</hierarchy>")
    if start < 0 or end < start:
        raise RuntimeError("UI hierarchy was not returned")
    return list(ET.fromstring(raw[start:end + len("</hierarchy>")]).iter("node"))


def describe(node):
    return {key: node.get(key) for key in (
        "text", "content-desc", "class", "clickable", "enabled", "bounds"
    )}


def tap(label, prefix=False):
    matches = [node for node in nodes()
               if any((value.startswith(label) if prefix else value == label)
                      for value in (node.get("text", ""), node.get("content-desc", "")))]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one UI match for {label!r}, found {len(matches)}")
    node = matches[0]
    bounds = [int(x) for x in re.findall(r"\d+", node.get("bounds", ""))]
    if len(bounds) != 4 or node.get("enabled") != "true":
        raise RuntimeError(f"UI target is not usable: {describe(node)}")
    print(json.dumps(describe(node)))
    print(adb("shell", "input", "tap", str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("dump", "tap", "tap-prefix", "focus", "type", "back", "home"))
    parser.add_argument("value", nargs="?")
    args = parser.parse_args()
    if args.action == "dump":
        for node in nodes():
            if node.get("text") or node.get("content-desc") or node.get("class") == "android.widget.EditText":
                print(json.dumps(describe(node)))
    elif args.action in {"tap", "tap-prefix"}:
        tap(args.value, prefix=args.action == "tap-prefix")
    elif args.action == "focus":
        matches = [node for node in nodes() if node.get("class") == "android.widget.EditText" and node.get("clickable") == "true"]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one editable composer, found {len(matches)}")
        bounds = [int(x) for x in re.findall(r"\d+", matches[0].get("bounds", ""))]
        print(adb("shell", "input", "tap", str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2)))
    elif args.action == "type":
        if not re.fullmatch(r"[A-Za-z0-9 ._-]+", args.value):
            raise ValueError("Probe accepts only plain fixture text, not shell metacharacters or secrets")
        print(adb("shell", "input", "text", args.value.replace(" ", "%s")))
    else:
        print(adb("shell", "input", "keyevent", "4" if args.action == "back" else "3"))
