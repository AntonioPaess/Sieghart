"""Exercise membership/preservation on disposable projects, without building."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read_project(path):
    return json.loads(subprocess.check_output(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)]))


class ProjectSourceChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sieghart-project-check-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "Tools").mkdir()
        (self.root / "Sieghart.xcodeproj").mkdir()
        self.project = self.root / "Sieghart.xcodeproj/project.pbxproj"
        shutil.copy2(ROOT / "Tools/update-project-sources.py", self.root / "Tools/update-project-sources.py")
        shutil.copy2(ROOT / "Sieghart.xcodeproj/project.pbxproj", self.project)
        for tree in ("Sieghart", "Tests/Support", "Tests/SwiftTesting", "Tests/TestPlans"):
            for path in (ROOT / tree).rglob("*"):
                if path.is_file() and path.suffix in (".swift", ".xctestplan"):
                    target = self.root / path.relative_to(ROOT)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.touch()

    def generate(self):
        subprocess.run(["python3", str(self.root / "Tools/update-project-sources.py")],
                       check=True, stdout=subprocess.DEVNULL)

    def source_ids(self, project, name):
        objects = project["objects"]
        target = next(v for v in objects.values() if v.get("isa") == "PBXNativeTarget" and v.get("name") == name)
        phase = next(objects[p] for p in target["buildPhases"] if objects[p]["isa"] == "PBXSourcesBuildPhase")
        return [objects[b]["fileRef"] for b in phase["files"]]

    def test_target_membership_is_separate_and_generation_is_idempotent(self):
        self.generate()
        first = self.project.read_bytes()
        self.generate()
        self.assertEqual(first, self.project.read_bytes())
        project = read_project(self.project)
        app = self.source_ids(project, "Sieghart")
        tests = self.source_ids(project, "SieghartTests")
        objects = project["objects"]
        self.assertEqual(len(app), len(set(app)))
        self.assertEqual(len(tests), len(set(tests)))
        app_only = {objects[f]["path"] for f in set(app) - set(tests)}
        self.assertEqual(app_only, {"SieghartApp.swift", "ResidentAppDelegate.swift"})
        self.assertTrue(set(tests) - set(app))

    def test_duplicate_basenames_use_distinct_paths_and_build_references(self):
        for parent in ("Core/Helpers", "Shared/Models"):
            file = self.root / "Sieghart" / parent / "MembershipProbe.swift"
            file.parent.mkdir(parents=True, exist_ok=True)
            file.touch()
        self.generate()
        project = read_project(self.project)
        objects = project["objects"]
        refs = {k for k, v in objects.items() if v.get("path") == "MembershipProbe.swift"}
        self.assertEqual(len(refs), 2)
        for name in ("Sieghart", "SieghartTests"):
            self.assertTrue(refs.issubset(self.source_ids(project, name)))
        first = self.project.read_bytes()
        self.generate()
        self.assertEqual(first, self.project.read_bytes())

    def test_unrelated_group_and_object_are_preserved(self):
        text = self.project.read_text()
        group = "D11111111111111111111111"
        file = "D22222222222222222222222"
        text = text.replace("/* End PBXFileReference section */",
            f'\t\t{file} /* custom.txt */ = {{isa = PBXFileReference; path = custom.txt; sourceTree = "<group>"; }};\n/* End PBXFileReference section */')
        text = text.replace("/* End PBXGroup section */",
            f'\t\t{group} /* Unrelated */ = {{isa = PBXGroup; children = ({file},); path = Unrelated; sourceTree = "<group>"; }};\n/* End PBXGroup section */')
        text = text.replace("A10000000000000000000006 /* Products */,",
                            f"A10000000000000000000006 /* Products */,\n\t\t\t\t{group},", 1)
        self.project.write_text(text)
        expected = read_project(self.project)["objects"]
        self.generate()
        actual = read_project(self.project)["objects"]
        self.assertEqual(expected[group], actual[group])
        self.assertEqual(expected[file], actual[file])
        app = "A1000000000000000000000A"
        self.assertEqual(expected[app], actual[app])
        for key in ("A1000000000000000000000F", "A10000000000000000000010",
                    "A10000000000000000000011", "A10000000000000000000012"):
            self.assertEqual(expected[key], actual[key])


if __name__ == "__main__":
    unittest.main()
