#!/usr/bin/env python3
"""capture-screenshots.py — Run UI screenshot tests and dump PNGs into
``agent/screenshots/`` so future agent sessions can read the current UI
state without running anything.

Pipeline:
  1. ``xcodebuild test`` on the UI screenshot suite (iOS by default,
     optionally watch).
  2. Walk the resulting ``.xcresult`` bundle via ``xcrun xcresulttool``
     to enumerate ``XCTAttachment`` records.
  3. Export every screenshot attachment to ``agent/screenshots/<platform>/``.
  4. Regenerate ``agent/screenshots/INDEX.md`` with embedded thumbnails
     so the folder is browsable.

Usage:
  ./agent/scripts/capture-screenshots.py                      # iOS only
  ./agent/scripts/capture-screenshots.py --platform watch     # watch only
  ./agent/scripts/capture-screenshots.py --platform all       # both
  ./agent/scripts/capture-screenshots.py --skip-build         # only extract
                                                              # from the last
                                                              # result bundle

Requires:
  * macOS with Xcode + at least one matching simulator runtime installed.
  * Python 3.9+ (only stdlib used).

Local simulator currently broken per AGENT.md — run this on a working
dev machine or wire it into Xcode Cloud and commit the resulting PNGs.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Optional

# ----- Defaults -----------------------------------------------------------

DEFAULT_IOS_DESTINATION = "platform=iOS Simulator,name=iPhone 16 Pro"
DEFAULT_WATCH_DESTINATION = "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)"
DEFAULT_SCHEME = "SpektoWatch2"
IOS_TEST_PATH = "SpektoWatch2UITests/ScreenshotCatalogTests"
WATCH_TEST_PATH = "SpektoWatch2UITests/WatchAppScreenshotTests"

# ----- Helpers ------------------------------------------------------------


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def repo_root() -> Path:
    here = Path(__file__).resolve()
    for parent in [here.parent, *here.parents]:
        if (parent / "SpektoWatch2.xcodeproj").exists():
            return parent
    raise RuntimeError(
        "Could not locate repo root (no SpektoWatch2.xcodeproj found)."
    )


def sanitize_filename(name: str) -> str:
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    return "".join(c if c in allowed else "_" for c in name).strip("_") or "screenshot"


def xcrun(args: list[str]) -> str:
    """Run an xcrun command and return stdout decoded as UTF-8."""
    result = subprocess.run(
        ["xcrun", *args], check=True, capture_output=True, text=True
    )
    return result.stdout


# ----- xcodebuild ---------------------------------------------------------


def run_xcodebuild(
    project: Path,
    scheme: str,
    destination: str,
    only_testing: str,
    derived_data: Path,
    result_bundle: Path,
) -> int:
    if result_bundle.exists():
        shutil.rmtree(result_bundle)
    derived_data.mkdir(parents=True, exist_ok=True)
    cmd = [
        "xcodebuild",
        "test",
        "-project", str(project),
        "-scheme", scheme,
        "-destination", destination,
        "-only-testing:" + only_testing,
        "-derivedDataPath", str(derived_data),
        "-resultBundlePath", str(result_bundle),
        "-quiet",
    ]
    log("$ " + " ".join(cmd))
    completed = subprocess.run(cmd)
    return completed.returncode


# ----- xcresulttool walk --------------------------------------------------


def get_json(xcresult: Path, ref_id: Optional[str] = None) -> dict:
    """xcrun xcresulttool get --format json [--id ID] --path PATH"""
    args = [
        "xcresulttool", "get",
        "--path", str(xcresult),
        "--format", "json",
        "--legacy",
    ]
    if ref_id:
        args.extend(["--id", ref_id])
    raw = xcrun(args)
    return json.loads(raw)


def export_attachment(xcresult: Path, payload_id: str, dest: Path) -> None:
    args = [
        "xcresulttool", "export",
        "--path", str(xcresult),
        "--id", payload_id,
        "--type", "file",
        "--output-path", str(dest),
        "--legacy",
    ]
    subprocess.run(["xcrun", *args], check=True)


def walk_attachments(node, callback) -> None:
    """Walk every dict/list in the JSON tree, invoking ``callback`` for any
    node containing an ``attachments`` field."""
    if isinstance(node, dict):
        attachments = node.get("attachments", {})
        if isinstance(attachments, dict):
            values = attachments.get("_values", [])
            for entry in values:
                callback(entry)
        for value in node.values():
            walk_attachments(value, callback)
    elif isinstance(node, list):
        for item in node:
            walk_attachments(item, callback)


def extract_screenshots(xcresult: Path, output_dir: Path) -> list[Path]:
    """Return the list of PNG paths written into ``output_dir``."""
    info = get_json(xcresult)
    actions = info.get("actions", {}).get("_values", [])
    written: list[Path] = []

    for action in actions:
        tests_ref = (
            action.get("actionResult", {})
            .get("testsRef", {})
            .get("id", {})
            .get("_value")
        )
        if not tests_ref:
            continue
        tests = get_json(xcresult, tests_ref)

        def on_attachment(entry):
            name_raw = entry.get("name", {}).get("_value")
            uti = entry.get("uniformTypeIdentifier", {}).get("_value", "")
            payload_id = entry.get("payloadRef", {}).get("id", {}).get("_value")
            if not name_raw or not payload_id:
                return
            # Only export PNG screenshots, ignore other attachment types.
            if "png" not in uti.lower() and "image" not in uti.lower():
                return
            dest = output_dir / f"{sanitize_filename(name_raw)}.png"
            export_attachment(xcresult, payload_id, dest)
            written.append(dest)
            log(f"   ↳ {dest.relative_to(repo_root())}")

        walk_attachments(tests, on_attachment)

    return written


# ----- Index generation ---------------------------------------------------


def write_index(root: Path, captures: dict[str, list[Path]]) -> None:
    index_path = root / "agent" / "screenshots" / "INDEX.md"
    timestamp = datetime.datetime.now().isoformat(timespec="seconds")
    lines: list[str] = [
        "# UI Screenshots — Current State",
        "",
        "_Captured automatically by `agent/scripts/capture-screenshots.py`._",
        f"_Last refresh: **{timestamp}**._",
        "",
        "These are the visual ground truth for the iOS app and the watch faces.",
        "Future agent sessions can read this folder to understand what the UI",
        "currently looks like without launching the app.",
        "",
    ]
    for platform, files in captures.items():
        if not files:
            continue
        lines.append(f"## {platform}")
        lines.append("")
        for png in sorted(files):
            rel = png.relative_to(index_path.parent)
            lines.append(f"### `{png.stem}`")
            lines.append("")
            lines.append(f"![{png.stem}]({rel})")
            lines.append("")
    index_path.write_text("\n".join(lines))
    log(f"Wrote {index_path.relative_to(root)}")


# ----- Orchestration ------------------------------------------------------


def capture_platform(
    platform: str,
    scheme: str,
    destination: str,
    only_testing: str,
    skip_build: bool,
) -> list[Path]:
    root = repo_root()
    project = root / "SpektoWatch2.xcodeproj"
    output_dir = root / "agent" / "screenshots" / platform
    output_dir.mkdir(parents=True, exist_ok=True)

    build_dir = root / ".build" / f"ui-screenshots-{platform}"
    result_bundle = build_dir / "result.xcresult"
    derived_data = build_dir / "derived"

    if not skip_build:
        log(f"\n=== Running screenshot suite for {platform} ===")
        rc = run_xcodebuild(
            project=project,
            scheme=scheme,
            destination=destination,
            only_testing=only_testing,
            derived_data=derived_data,
            result_bundle=result_bundle,
        )
        if rc != 0:
            log(f"⚠️  xcodebuild exited with code {rc}. Attempting extraction anyway.")
    elif not result_bundle.exists():
        log(f"⚠️  --skip-build given but no result bundle at {result_bundle}")
        return []

    # Clear existing platform screenshots so dropped tests don't leave stale PNGs.
    for png in output_dir.glob("*.png"):
        png.unlink()

    log(f"Extracting attachments from {result_bundle.relative_to(root)} …")
    return extract_screenshots(result_bundle, output_dir)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--platform",
        choices=["ios", "watch", "all"],
        default="ios",
        help="Which platform to capture (default: ios).",
    )
    parser.add_argument(
        "--scheme",
        default=DEFAULT_SCHEME,
        help=f"Xcode scheme (default: {DEFAULT_SCHEME}).",
    )
    parser.add_argument(
        "--ios-destination",
        default=DEFAULT_IOS_DESTINATION,
        help=f"iOS simulator destination (default: {DEFAULT_IOS_DESTINATION}).",
    )
    parser.add_argument(
        "--watch-destination",
        default=DEFAULT_WATCH_DESTINATION,
        help=f"watchOS simulator destination (default: {DEFAULT_WATCH_DESTINATION}).",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip xcodebuild and only re-extract from the last result bundle.",
    )
    args = parser.parse_args()

    captures: dict[str, list[Path]] = {}

    if args.platform in ("ios", "all"):
        captures["ios"] = capture_platform(
            platform="ios",
            scheme=args.scheme,
            destination=args.ios_destination,
            only_testing=IOS_TEST_PATH,
            skip_build=args.skip_build,
        )

    if args.platform in ("watch", "all"):
        captures["watch"] = capture_platform(
            platform="watch",
            scheme=args.scheme,
            destination=args.watch_destination,
            only_testing=WATCH_TEST_PATH,
            skip_build=args.skip_build,
        )

    write_index(repo_root(), captures)

    total = sum(len(v) for v in captures.values())
    log(f"\n✓ Captured {total} screenshots.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
