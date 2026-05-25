"""Unit tests for the attachment-walking helpers in capture-screenshots.py.

Run with:
  python3 -m unittest agent/scripts/test_capture_screenshots.py

No Xcode or simulator required.
"""

import sys
import os
import unittest
from pathlib import Path

# Allow importing from the same directory without an __init__.py.
sys.path.insert(0, str(Path(__file__).parent))
import importlib.util

_spec = importlib.util.spec_from_file_location(
    "capture_screenshots",
    Path(__file__).with_name("capture-screenshots.py"),
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

_as_list = _mod._as_list
_str_value = _mod._str_value
walk_attachments = _mod.walk_attachments


# ---------------------------------------------------------------------------
# _as_list
# ---------------------------------------------------------------------------

class TestAsList(unittest.TestCase):

    def test_plain_list(self):
        self.assertEqual(_as_list([1, 2, 3]), [1, 2, 3])

    def test_legacy_dict_with_values_key(self):
        self.assertEqual(_as_list({"_values": [4, 5]}), [4, 5])

    def test_legacy_dict_missing_values_key(self):
        self.assertEqual(_as_list({"other": 1}), [])

    def test_empty_list(self):
        self.assertEqual(_as_list([]), [])

    def test_none(self):
        self.assertEqual(_as_list(None), [])

    def test_scalar(self):
        self.assertEqual(_as_list("hello"), [])

    def test_nested_list_in_dict_not_a_list(self):
        self.assertEqual(_as_list({"_values": "oops"}), [])


# ---------------------------------------------------------------------------
# _str_value
# ---------------------------------------------------------------------------

class TestStrValue(unittest.TestCase):

    def test_plain_string(self):
        self.assertEqual(_str_value("hello"), "hello")

    def test_legacy_dict_value(self):
        self.assertEqual(_str_value({"_value": "world"}), "world")

    def test_legacy_dict_missing_value(self):
        self.assertIsNone(_str_value({"other": "x"}))

    def test_none(self):
        self.assertIsNone(_str_value(None))

    def test_int(self):
        self.assertIsNone(_str_value(42))


# ---------------------------------------------------------------------------
# walk_attachments
# ---------------------------------------------------------------------------

def _make_attachment(name: str, uti: str = "public.png", payload_id: str = "abc123"):
    """Build a minimal attachment node in legacy (dict) format."""
    return {
        "name": {"_value": name},
        "uniformTypeIdentifier": {"_value": uti},
        "payloadRef": {"id": {"_value": payload_id}},
    }


def _make_attachment_modern(name: str, uti: str = "public.png", payload_id: str = "abc123"):
    """Build a minimal attachment node in modern (plain-string) format."""
    return {
        "name": name,
        "uniformTypeIdentifier": uti,
        "payloadRef": {"id": payload_id},
    }


class TestWalkAttachments(unittest.TestCase):

    def _collect(self, tree):
        collected = []
        walk_attachments(tree, collected.append)
        return collected

    # --- Legacy dict format ---

    def test_legacy_dict_attachments(self):
        tree = {"attachments": {"_values": [_make_attachment("shot1"), _make_attachment("shot2")]}}
        result = self._collect(tree)
        self.assertEqual(len(result), 2)

    def test_legacy_single_attachment(self):
        tree = {"attachments": {"_values": [_make_attachment("only")]}}
        result = self._collect(tree)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["name"]["_value"], "only")

    # --- Modern list format (ACP M18-task-5 fallback) ---

    def test_modern_list_attachments(self):
        tree = {"attachments": [_make_attachment_modern("a"), _make_attachment_modern("b")]}
        result = self._collect(tree)
        self.assertEqual(len(result), 2)

    # --- Empty / malformed ---

    def test_empty_attachments_dict(self):
        result = self._collect({"attachments": {"_values": []}})
        self.assertEqual(result, [])

    def test_empty_attachments_list(self):
        result = self._collect({"attachments": []})
        self.assertEqual(result, [])

    def test_no_attachments_key(self):
        result = self._collect({"other": "data"})
        self.assertEqual(result, [])

    def test_malformed_attachments_scalar(self):
        result = self._collect({"attachments": "oops"})
        self.assertEqual(result, [])

    def test_nested_tree(self):
        inner = {"attachments": {"_values": [_make_attachment("deep")]}}
        outer = {"children": [inner]}
        result = self._collect(outer)
        self.assertEqual(len(result), 1)

    def test_both_formats_in_same_tree(self):
        legacy = {"attachments": {"_values": [_make_attachment("leg")]}}
        modern = {"attachments": [_make_attachment_modern("mod")]}
        tree = {"a": legacy, "b": modern}
        result = self._collect(tree)
        self.assertEqual(len(result), 2)


if __name__ == "__main__":
    unittest.main()
