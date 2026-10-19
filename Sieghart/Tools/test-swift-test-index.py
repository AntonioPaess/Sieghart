"""Guard the Xcode selection boundary without invoking a compiler."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("swift_test_index", ROOT / "Tools/swift-test-index.py")
index = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = index
spec.loader.exec_module(index)


class SelectionChecks(unittest.TestCase):
    def test_native_swift_testing_tree(self):
        # Format saved by Xcode's test-plan editor, including nested suites.
        self.assertEqual(index.swift_testing_selection([
            "LogicTests/ExampleTests/second(_:)", "LogicTests/ExampleTests/first()",
        ]), {"suites": [{"name": "LogicTests", "suites": [{"name": "ExampleTests",
            "testFunctions": ["first()", "second(_:)"]}]}]})

    def test_unknown_runtime_leaf_is_rejected(self):
        with self.assertRaisesRegex(index.IndexError, "Unknown enumerated test"):
            index.enumerated_records({"values": [{"kind": "target", "name": "SieghartTests",
                "children": [{"kind": "test", "name": "missing()"}]}]}, {})

    def test_unknown_selection_never_creates_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            enumeration, output = directory / "discovery.json", directory / "index.json"
            enumeration.write_text(json.dumps({"values": [{"kind": "target", "name": "SieghartTests",
                "children": [{"kind": "class", "name": "LogicTests", "children": [
                    {"kind": "suite", "name": "VoiceIntentTests", "children": [
                        {"kind": "test", "name": "urlEncoding()"}]}]}]}]}))
            for filters in ({"filter": "no-such-group", "only": None},
                            {"filter": None, "only": "LogicTests/NoSuchSuite/missing()"}):
                with self.subTest(filters=filters), self.assertRaises(index.IndexError):
                    index.run(argparse.Namespace(enumeration=enumeration, output=output,
                        selectors=None, fast_plan=None, plan="complete", **filters))
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
