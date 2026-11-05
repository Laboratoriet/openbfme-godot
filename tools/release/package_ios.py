#!/usr/bin/env python3
"""Export OpenBFME's iOS / iPadOS Xcode project (docs/IOS.md).

    tools/release/build_ios.sh                       # godot/bin/openbfme.ios.xcframework
    python3 tools/release/package_ios.py [--team-id TEAM] [--bundle-id ID] [--templates Godot_v4.7.2-stable_export_templates.tpz]

The project folder godot/ is copied to a stage (without its import cache, bin/, mods/ and retail/), the iOS extension and the host's
macOS extension are put in the stage's bin/ (the editor imports the scripts with the host's), the "iOS" preset is exported as an Xcode
project, and the generated project is adjusted: the Info.plist keys and the entitlement below, and no placeholder team. Signing and the
build happen in Xcode (or xcodebuild) with the player's own Apple team; nothing here holds a team or a personal bundle id.

The staging, the preset chosen by its name and platform, the team placeholder and the Info.plist edits through plistlib follow
daisyhasacat/openbfme-godot's package_ios.py.
"""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_icon  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
NAME = "OpenBFME"
# Godot needs a team id to export, even an Xcode project only; this one is removed from the generated project again
TEAM_PLACEHOLDER = "UNSIGNED00"

# The app's Info.plist, on top of what Godot's template writes (each value with its reason).
INFO_PLIST = {
    # Godot's template marks the app full screen only. On a foldable's or an iPad's larger screen such an app runs in a compatibility mode
    # (drawn at another screen's size and scaled); a resizable app gets the window it is shown in, at the screen's own pixels.
    "UIRequiresFullScreen": False,
    # the app's Documents folder (Godot's user://: settings, saves, logs, install-paths.cfg) is shown in Finder's device window and in
    # the Files app (On My iPhone > OpenBFME), so a player can copy files there
    "UIFileSharingEnabled": True,
    "LSSupportsOpeningDocumentsInPlace": True,
    # a mouse or trackpad click reaches the app as an indirect pointer touch (UIEvent.buttonMask tells its button), not as a finger
    "UIApplicationSupportsIndirectInputEvents": True,
}
# The app's entitlements. The increased memory limit: a skirmish holds about 1 GB of video memory besides the game's archives, close to
# iOS's default per-app limit on phones; Xcode's automatic signing adds the capability to the App ID.
ENTITLEMENTS = {
    "com.apple.developer.kernel.increased-memory-limit": True,
}


def ios_preset_options(text: str) -> tuple[int, int]:
    """The span of the options section of the one preset named "iOS" on the iOS platform (preset numbers change as presets are added)."""
    candidates = []
    for match in re.finditer(r'^\[preset\.(\d+)\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S):
        body = match.group(2)
        if re.search(r'^name="iOS"\s*$', body, re.M) and re.search(r'^platform="iOS"\s*$', body, re.M):
            candidates.append(match.group(1))
    if len(candidates) != 1:
        raise ValueError("Expected exactly one iOS export preset")
    section = re.search(r'^\[preset\.' + candidates[0] + r'\.options\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S)
    if section is None:
        raise ValueError("The iOS export preset has no options section")
    return section.start(1), section.end(1)


def configure_ios_preset(text: str, values: dict[str, str]) -> str:
    """Set options of the iOS preset; an option the preset does not list yet is added to its section."""
    start, end = ios_preset_options(text)
    options = text[start:end]
    for key, value in values.items():
        line = key + "=" + json.dumps(value)
        options, count = re.subn(r'^' + re.escape(key) + r'=.*$', lambda _: line, options, flags=re.M)
        if count > 1:
            raise ValueError("The iOS preset lists an option twice: " + key)
        if count == 0:
            body = options.rstrip("\n")
            options = body + "\n" + line + (options[len(body):] or "\n")
    return text[:start] + options + text[end:]


def preset_option(text: str, key: str) -> str | None:
    start, end = ios_preset_options(text)
    match = re.search(r'^' + re.escape(key) + r'=(.*)$', text[start:end], re.M)
    return json.loads(match.group(1)) if match else None


def patch_plist(path: Path, values: dict) -> list[str]:
    """Set keys in a property list (Info.plist, .entitlements), keeping every other key; returns the keys that changed."""
    data = plistlib.loads(path.read_bytes())
    changed = [key for key, value in values.items() if data.get(key) != value]
    if changed:
        data.update(values)
        path.write_bytes(plistlib.dumps(data))
    return changed


def strip_team_placeholder(project: Path) -> None:
    """Remove the placeholder team from project.pbxproj; Xcode then asks for the player's own."""
    text = project.read_text(encoding="utf-8")
    project.write_text(text.replace(TEAM_PLACEHOLDER, '""'), encoding="utf-8")


def ios_template(tpz: Path, build: Path) -> Path:
    """templates/ios.zip from Godot's official export templates (.tpz), checked against the editor's version."""
    with zipfile.ZipFile(tpz) as archive:
        version = archive.read("templates/version.txt").decode().strip()
        target = build / f"ios-{version}.zip"
        if not target.exists():
            partial = target.with_suffix(".partial")
            partial.write_bytes(archive.read("templates/ios.zip"))
            partial.replace(target)
    return target


def write_icon(target: Path) -> None:
    """The 1024 px App Store / home screen icon, made from the project's own icon (openbfme.ico's 256 px frame) at export time."""
    frame = target.with_suffix(".256.png")
    frame.write_bytes(app_icon.read_ico(app_icon.SOURCE.read_bytes())[256])
    subprocess.run(["sips", "-z", "1024", "1024", str(frame), "--out", str(target)], check=True, stdout=subprocess.DEVNULL)
    frame.unlink()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--team-id", default=os.environ.get("APPLE_TEAM_ID", ""), help="your Apple development team (optional: or in Xcode)")
    parser.add_argument("--bundle-id", default=os.environ.get("OPENBFME_IOS_BUNDLE_ID", ""),
                        help="the app's bundle id (default: the preset's org.openbfme.game)")
    parser.add_argument("--templates", type=Path, help="Godot's official export templates (.tpz); default: the editor's installed ones")
    parser.add_argument("--build-dir", type=Path, default=ROOT / "engine/build/ios-export")
    parser.add_argument("--output-dir", type=Path, help="a new folder for the Xcode project (default: <build dir>/export)")
    args = parser.parse_args(argv)

    xcframework = ROOT / "godot/bin/openbfme.ios.xcframework"
    if not xcframework.is_dir():
        parser.error("no godot/bin/openbfme.ios.xcframework: run tools/release/build_ios.sh first")
    hosts = sorted((ROOT / "godot/bin").glob("openbfme.macos.*.dylib"))
    if not hosts:
        parser.error("no macOS extension in godot/bin: build it first (README, Build from source); the editor imports with it")
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    output = (args.output_dir.resolve() if args.output_dir else build / "export")
    project = output / f"{NAME}.xcodeproj"
    if project.exists():
        parser.error(f"{project} exists already: choose a new --output-dir (an export is never overwritten)")
    output.mkdir(parents=True, exist_ok=True)

    values = {"application/app_store_team_id": args.team_id or TEAM_PLACEHOLDER,
              "icons/icon_1024x1024": "res://assets/app_icon/ios-1024.png"}
    if args.bundle_id:
        values["application/bundle_identifier"] = args.bundle_id
    if args.templates:
        template = str(ios_template(args.templates.resolve(), build))
        values["custom_template/debug"] = values["custom_template/release"] = template

    with tempfile.TemporaryDirectory(prefix="ios-stage-", dir=build) as temp:
        stage = Path(temp) / "godot"
        shutil.copytree(ROOT / "godot", stage, ignore=shutil.ignore_patterns(".godot", "bin", "mods", "retail"))
        (stage / "bin").mkdir()
        shutil.copytree(xcframework, stage / "bin" / xcframework.name, symlinks=True)
        for host in hosts:
            shutil.copy2(host, stage / "bin" / host.name)
        write_icon(stage / "assets/app_icon/ios-1024.png")  # a folder with a .gdignore: read by path, not packed
        presets = stage / "export_presets.cfg"
        presets.write_text(configure_ios_preset(presets.read_text(encoding="utf-8"), values), encoding="utf-8")
        subprocess.run([args.godot, "--headless", "--path", str(stage), "--editor", "--import", "--quit"], check=True)
        subprocess.run([args.godot, "--headless", "--path", str(stage), "--export-debug", "iOS", str(project)], check=True)

    if not project.is_dir():
        print(f"no Xcode project at {project}: see Godot's output above", file=sys.stderr)
        return 1
    if not args.team_id:
        strip_team_placeholder(project / "project.pbxproj")
    for path, keys in ((output / NAME / f"{NAME}-Info.plist", INFO_PLIST), (output / NAME / f"{NAME}.entitlements", ENTITLEMENTS)):
        if not path.is_file():
            print(f"no {path} in the export: Godot's iOS template changed", file=sys.stderr)
            return 1
        patch_plist(path, keys)
    print(f"EXPORTED {project}")
    print("Open it in Xcode, choose your team under Signing & Capabilities and run it on your device, or build it with")
    print(f"  xcodebuild -project {project} -scheme {NAME} -sdk iphoneos -configuration Debug -allowProvisioningUpdates "
          "DEVELOPMENT_TEAM=<your team> build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
