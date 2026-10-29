#!/usr/bin/env python3
"""Build, install, inspect and restore the version-pinned Easydict patch."""

import argparse
from datetime import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import time

from inject_dylib import inject

ROOT = Path(__file__).resolve().parent.parent
VERSION = "2.23.0"
LIBRARY = "@rpath/libeasydict_patch.dylib"


def run(*command):
    return subprocess.run([str(value) for value in command], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def info(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        metadata = plistlib.load(stream)
    if metadata.get("CFBundleIdentifier") != "com.izual.Easydict":
        raise ValueError("Target is not Easydict (bundle identifier mismatch)")
    executable = metadata.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise ValueError("Invalid bundle executable")
    return metadata, app / "Contents/MacOS" / executable


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stop_target(binary):
    processes = run("/bin/ps", "-axo", "pid=,comm=").stdout.splitlines()
    pids = []
    for line in processes:
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1] == str(binary):
            pids.append(int(fields[0]))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 8
    while pids and time.monotonic() < deadline:
        remaining = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                remaining.append(pid)
            except ProcessLookupError:
                pass
        pids = remaining
        if pids:
            time.sleep(0.1)
    if pids:
        raise ValueError("Easydict did not quit. Quit it manually and retry; no force-kill was used")


def doctor(app):
    metadata, binary = info(app)
    version = metadata.get("CFBundleShortVersionString")
    print("App version:", version, "(kit supports %s only)" % VERSION)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    print("On-disk signature: valid")
    present = (app / "Contents/Frameworks/libeasydict_patch.dylib").is_file()
    loaded = LIBRARY in run("/usr/bin/otool", "-L", binary).stdout
    print("Patch file:", "present" if present else "absent")
    print("Patch load command:", "present" if loaded else "absent")
    print("Static inspection only. Real selection, macOS authorization and audible playback must be checked manually.")
    print("If selection is blocked after signing: remove the OLD Easydict entry in Privacy & Security > Accessibility,")
    print("add this exact app again, enable it, approve Touch ID yourself, then restart Easydict.")


def preflight(app):
    if sys.platform != "darwin":
        raise ValueError("This kit runs on macOS only")
    metadata, binary = info(app)
    if metadata.get("CFBundleShortVersionString") != VERSION:
        raise ValueError("Refusing an unvalidated app version; this kit supports %s only" % VERSION)
    for tool in ("/usr/bin/ditto", "/usr/bin/codesign", "/usr/bin/otool", "/usr/bin/xcrun"):
        if not Path(tool).is_file():
            raise ValueError("Missing tool: " + tool)
    run("/usr/bin/xcrun", "--find", "clang")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    if not os.access(app.parent, os.W_OK):
        raise ValueError("No write access to the app folder. Do not run this script with sudo")
    return binary


def backup(app, base):
    base.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix=datetime.now().strftime("%Y%m%d-%H%M%S-"), dir=str(base)))
    destination = folder / "Easydict.app"
    run("/usr/bin/ditto", app, destination)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", destination)
    print("Recoverable backup:", destination)
    return destination


def replace_app(staged, app, binary, expected_hash, backup_base):
    # Stage and sign first; the installed app remains untouched on build failure.
    if backup_base == app or app in backup_base.parents:
        raise ValueError("Backup folder must be outside the installed app")
    if digest(binary) != expected_hash:
        raise ValueError("Installed executable changed during preparation; retry after its update finishes")
    stop_target(binary)
    if digest(binary) != expected_hash:
        raise ValueError("Installed executable changed while quitting; refusing to replace it")
    saved = backup(app, backup_base)
    previous = staged.parent / "previous.app"
    os.replace(app, previous)
    try:
        os.replace(staged, app)
    except BaseException:
        os.replace(previous, app)
        raise
    print("Installed:", app)
    print("Before testing selection, refresh its Accessibility entry using docs/USER-NOTEBOOK.zh-CN.md.")
    print("To restore this exact previous app: python3 scripts/kit.py restore --backup", saved)


def install(app, backup_base):
    binary = preflight(app)
    original_hash = digest(binary)
    with tempfile.TemporaryDirectory(prefix=".easydict-kit-", dir=str(app.parent)) as work:
        staged = Path(work) / "Easydict.app"
        run("/usr/bin/ditto", app, staged)
        _, staged_binary = info(staged)
        library = staged / "Contents/Frameworks/libeasydict_patch.dylib"
        library.parent.mkdir(parents=True, exist_ok=True)
        run("/usr/bin/xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-arch", "x86_64",
            "-fobjc-arc", "-framework", "Foundation", "-framework", "AppKit", "-framework", "AVFoundation",
            "-install_name", LIBRARY, ROOT / "src/libeasydict_patch.m", "-o", library)
        inject(staged_binary, LIBRARY)
        run("/usr/bin/codesign", "--force", "--sign", "-", library)
        run("/usr/bin/codesign", "--force", "--sign", "-",
            "--preserve-metadata=identifier,entitlements,flags,runtime", staged)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", staged)
        if LIBRARY not in run("/usr/bin/otool", "-L", staged_binary).stdout:
            raise ValueError("Staged app does not load the patch")
        replace_app(staged, app, binary, original_hash, backup_base)
    print("Launch Easydict from Applications when ready. This installer does not reset or grant permissions.")


def restore(app, saved, backup_base):
    _, binary = info(app)
    info(saved)
    if saved == app or saved in app.parents or app in saved.parents:
        raise ValueError("Backup and installed app must be independent directories")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", saved)
    original_hash = digest(binary)
    with tempfile.TemporaryDirectory(prefix=".easydict-restore-", dir=str(app.parent)) as work:
        staged = Path(work) / "Easydict.app"
        run("/usr/bin/ditto", saved, staged)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", staged)
        replace_app(staged, app, binary, original_hash, backup_base)
    print("Restore complete. Backups and translation preferences were retained.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("doctor", "install", "restore"))
    parser.add_argument("--app", type=Path, default=Path("/Applications/Easydict.app"))
    parser.add_argument("--backup", type=Path, help="Exact backup .app path for restore")
    parser.add_argument("--backup-dir", type=Path,
                        default=Path.home() / "Library/Application Support/EasydictPronunciationKit/backups")
    args = parser.parse_args()
    try:
        if os.geteuid() == 0:
            raise ValueError("Run as your normal macOS user, without sudo")
        app = args.app.expanduser().resolve()
        backup_base = args.backup_dir.expanduser().resolve()
        if args.action == "doctor":
            doctor(app)
        elif args.action == "install":
            install(app, backup_base)
        else:
            if not args.backup:
                raise ValueError("restore requires --backup /path/to/backup/Easydict.app")
            restore(app, args.backup.expanduser().resolve(), backup_base)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        parser.exit(1, "Stopped: %s\n" % detail)


if __name__ == "__main__":
    main()
