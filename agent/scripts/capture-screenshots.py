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

Local one-command recipe (run on a working dev machine or CI):

  xcodebuild test \\
    -scheme SpektoWatch2 \\
    -destination 'platform=iOS Simulator,name=iPhone 15' \\
    -resultBundlePath ./TestResults/local.xcresult \\
    -only-testing:SpektoWatch2UITests
  python3 agent/scripts/capture-screenshots.py --skip-build

Or to extract from an existing .xcresult directly:

  python3 agent/scripts/capture-screenshots.py \\
    --xcresult ./TestResults/local.xcresult \\
    --output   ./TestResults/Screenshots

Unit tests (no Xcode required):
  python3 -m unittest agent/scripts/test_capture_screenshots.py

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


# ACP M18-task-5: xcresulttool output shape changed across Xcode versions.
# Legacy format wraps arrays as {"_values": [...]}; newer format uses a
# plain list.  _as_list() normalises both so callers are format-agnostic.
def _as_list(node) -> list:
    """Return the list contained in *node* regardless of xcresulttool format.

    * Legacy format: ``{"_values": [...], ...}``
    * Modern format: ``[...]``
    * Anything else (None, scalar, malformed): ``[]``
    """
    if isinstance(node, list):
        return node
    if isinstance(node, dict):
        values = node.get("_values", [])
        return values if isinstance(values, list) else []
    return []


def _str_value(node) -> Optional[str]:
    """Return the string contained in *node* regardless of xcresulttool format.

    * Legacy format: ``{"_value": "..."}``
    * Modern format: plain string
    * Anything else: ``None``
    """
    if isinstance(node, str):
        return node
    if isinstance(node, dict):
        v = node.get("_value")
        return v if isinstance(v, str) else None
    return None


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


def walk_attachments(node, callback, xcresult: Optional[Path] = None,
                     _visited: Optional[set] = None) -> None:
    """Walk every dict/list in the JSON tree, invoking ``callback`` for any
    node containing an ``attachments`` field.

    In newer Xcode/xcresulttool builds, the test-activity data lives under a
    ``Reference`` node that must be fetched separately.  When *xcresult* is
    provided this function follows those references automatically so that
    screenshots attached inside ``activitySummaries`` are not missed.
    """
    if _visited is None:
        _visited = set()

    # JSON-typed target names that we know are fetchable summaries.
    _FOLLOW_TYPES = {
        "ActionTestSummary",
        "ActionTestActivitySummary",
        "ActionTestPlanRunSummary",
        "ActionTestableSummary",
        "ActionTestSuite",
        "ActionTestMetadata",
    }

    if isinstance(node, dict):
        # Follow Reference nodes whose target type is a known JSON summary.
        # Do NOT follow payloadRef and other binary references.
        t = node.get("_type", {}).get("_name", "")
        if t == "Reference" and xcresult is not None:
            target_type = _str_value(
                node.get("targetType", {}).get("name", {})
            ) or ""
            ref_id = _str_value(node.get("id", {}))
            if ref_id and ref_id not in _visited and target_type in _FOLLOW_TYPES:
                _visited.add(ref_id)
                try:
                    sub = get_json(xcresult, ref_id)
                    walk_attachments(sub, callback, xcresult, _visited)
                except Exception:
                    pass  # Skip unfetchable references gracefully.
            return

        attachments = node.get("attachments")
        if attachments is not None:
            for entry in _as_list(attachments):
                callback(entry)
        for value in node.values():
            walk_attachments(value, callback, xcresult, _visited)
    elif isinstance(node, list):
        for item in node:
            walk_attachments(item, callback, xcresult, _visited)


def extract_screenshots(xcresult: Path, output_dir: Path) -> list[Path]:
    """Return the list of PNG paths written into ``output_dir``."""
    info = get_json(xcresult)
    actions = _as_list(info.get("actions", []))
    written: list[Path] = []

    for action in actions:
        action_result = action.get("actionResult", {}) if isinstance(action, dict) else {}
        tests_ref_node = action_result.get("testsRef", {}) if isinstance(action_result, dict) else {}
        id_node = tests_ref_node.get("id", {}) if isinstance(tests_ref_node, dict) else {}
        tests_ref = _str_value(id_node)
        if not tests_ref:
            continue
        tests = get_json(xcresult, tests_ref)

        def on_attachment(entry):
            if not isinstance(entry, dict):
                return
            name_raw = _str_value(entry.get("name", {}))
            uti = _str_value(entry.get("uniformTypeIdentifier", {})) or ""
            payload_ref = entry.get("payloadRef", {})
            payload_id_node = payload_ref.get("id", {}) if isinstance(payload_ref, dict) else {}
            payload_id = _str_value(payload_id_node)
            if not name_raw or not payload_id:
                return
            # Only export PNG screenshots, ignore other attachment types.
            if "png" not in uti.lower() and "image" not in uti.lower():
                return
            dest = output_dir / f"{sanitize_filename(name_raw)}.png"
            export_attachment(xcresult, payload_id, dest)
            written.append(dest)
            log(f"   ↳ {dest.relative_to(repo_root())}")

        walk_attachments(tests, on_attachment, xcresult=xcresult)

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
    parser.add_argument(
        "--xcresult",
        default=None,
        help="Extract screenshots directly from this .xcresult path (skips build).",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output directory for extracted screenshots (used with --xcresult).",
    )
    args = parser.parse_args()

    # Direct extraction mode: bypass the full orchestration.
    if args.xcresult:
        xcresult = Path(args.xcresult)
        out = Path(args.output) if args.output else xcresult.parent / "Screenshots"
        out.mkdir(parents=True, exist_ok=True)
        written = extract_screenshots(xcresult, out)
        if not written:
            log("⚠️  No screenshots found in the xcresult bundle.")
            return 1
        log(f"\n✓ Extracted {len(written)} screenshots to {out}")
        return 0

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
