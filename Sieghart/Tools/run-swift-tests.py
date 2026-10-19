"""Build, discover, select and run unhosted Swift Testing with durable evidence."""
from pathlib import Path
import argparse
import collections
import fcntl
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, log):
    with log.open("wb") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(errors="replace")[-14000:], file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, command)


def capture_json(command, path, log):
    with path.open("wb") as stream, log.open("wb") as errors:
        result = subprocess.run(command, stdout=stream, stderr=errors)
    result.check_returncode()
    return json.loads(path.read_text())


def nodes(value):
    if isinstance(value, dict):
        if "nodeType" in value:
            yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", choices=("complete", "fast"), default="complete")
    parser.add_argument("--filter", default=os.environ.get("SIEGHART_CHECK_FILTER"))
    parser.add_argument("--only", help="Exact discovered test identifier, including function arguments")
    parser.add_argument("--output", type=Path, help="New directory for logs, discovery, results and coverage")
    parser.add_argument("--derived-data", type=Path)
    args = parser.parse_args()
    # Fail before any build for invalid/empty legacy filters.
    if args.filter:
        import re
        groups = ["timer", "callbacks", "voice-integration", "interactions", "companions", "usage",
                  "spending", "activity", "pricing", "audio", "imports", "clipboard", "middle-click",
                  "utilities", "calendar", "files-capture", "agent-room", "local-chat", "new-codex-chat"]
        try:
            if not any(re.search(args.filter, name) for name in groups):
                parser.error("The filter matches no legacy group; no tests were run.")
        except re.error as error:
            parser.error(f"Invalid group filter: {error}")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="sieghart-tests-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    print(f"Evidence: {output}", flush=True)
    # Reuse the exact project, omitting personal workspace state. Sources remain
    # the real files, not copies or alternate implementations.
    derived = args.derived_data.resolve() if args.derived_data else output / "DerivedData"
    derived.mkdir(parents=True, exist_ok=True)
    # A stable source path lets Xcode reuse compilation between output bundles.
    # Keep an exclusive lock for this invocation so another run cannot change its plan.
    cache_lock = (derived / ".sieghart-tests.lock").open("a+")
    try:
        fcntl.flock(cache_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("This derived-data directory is already running Sieghart tests.")
    snapshot = derived / "SourceWorkspace"
    marker = snapshot / ".sieghart-source-root"
    if snapshot.exists() and (not marker.is_file() or marker.read_text() != str(ROOT)):
        raise RuntimeError("Refusing to overwrite an unrecognized source workspace.")
    snapshot.mkdir(exist_ok=True)
    marker.write_text(str(ROOT))
    shutil.copytree(ROOT / "Sieghart.xcodeproj", snapshot / "Sieghart.xcodeproj",
                    ignore=shutil.ignore_patterns("xcuserdata", "project.xcworkspace"), dirs_exist_ok=True)
    (snapshot / "Tests").mkdir(exist_ok=True)
    for directory in ("Sieghart", "Tests/Support", "Tests/SwiftTesting"):
        link = snapshot / directory
        if link.is_symlink() and link.resolve() == (ROOT / directory).resolve():
            continue
        link.symlink_to(ROOT / directory, target_is_directory=True)
    shutil.copytree(ROOT / "Tests" / "TestPlans", snapshot / "Tests" / "TestPlans", dirs_exist_ok=True)
    architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
    base = ["xcodebuild", "-project", str(snapshot / "Sieghart.xcodeproj"),
            "-scheme", "Sieghart-Checks", "-destination", f"platform=macOS,arch={architecture}",
            "-derivedDataPath", str(derived), "-parallel-testing-enabled", "NO",
            "-maximum-parallel-testing-workers", "1"]
    manifest = {}
    for directory in ("Sieghart", "Tests/SwiftTesting", "Tests/Support"):
        for file in sorted((ROOT / directory).rglob("*.swift")):
            manifest[str(file.relative_to(ROOT))] = hashlib.sha256(file.read_bytes()).hexdigest()
    (output / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    run(base + ["-testPlan", "Sieghart-Complete", "test", "-enumerate-tests",
                "-test-enumeration-style", "hierarchical", "-test-enumeration-format", "json",
                "-test-enumeration-output-path", str(output / "discovery.json")], output / "discovery.log")
    selection = [sys.executable, str(ROOT / "Tools/swift-test-index.py"),
                 "--enumeration", str(output / "discovery.json"), "--output", str(output / "test-index.json"),
                 "--fast-plan", str(snapshot / "Tests/TestPlans/Sieghart-Fast.xctestplan"),
                 "--plan", args.plan, "--selectors", str(output / "selectors.txt")]
    if args.filter:
        selection += ["--filter", args.filter]
    if args.only:
        selection += ["--only", args.only]
    run(selection, output / "selection.log")
    index = json.loads((output / "test-index.json").read_text())
    if index["summary"]["sourceOnlyTests"]:
        raise RuntimeError("Complete discovery omitted source tests; refusing incomplete evidence.")
    selectors = (output / "selectors.txt").read_text().splitlines()
    if not selectors:
        raise RuntimeError("No tests selected; refusing a false successful run.")
    plan_name = "Sieghart-Complete" if args.plan == "complete" else "Sieghart-Fast"
    command = base + ["-testPlan", plan_name, "-resultBundlePath", str(output / "Results.xcresult"),
                      "-enableCodeCoverage", "YES", "test"]
    if args.filter or args.only:
        command += ["-only-testing:" + selector for selector in selectors]
    print(f"{len(selectors)} discovered test functions selected ({plan_name}).", flush=True)
    with (output / "tests.log").open("wb") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if not (output / "Results.xcresult").exists():
        raise RuntimeError("Xcode produced no result bundle; see tests.log.")
    summary = capture_json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
                            str(output / "Results.xcresult")], output / "summary.json", output / "summary.log")
    tests = capture_json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path",
                          str(output / "Results.xcresult")], output / "test-results.json", output / "test-results.log")
    cases = [node for node in nodes(tests) if node.get("nodeType") == "Test Case"]
    actual = {"SieghartTests/" + node["nodeIdentifier"] for node in cases}
    missing, unexpected = set(selectors) - actual, actual - set(selectors)
    functions = collections.Counter(node.get("result", "Unknown") for node in cases)
    by_identifier = {"SieghartTests/" + node["nodeIdentifier"]: node for node in cases}
    contracts = collections.defaultdict(list)
    for record in index["records"]:
        if not record["selected"]:
            continue
        case = by_identifier.get(record["identifier"], {})
        for contract in record["contractIDs"]:
            contracts[contract].append({"identifier": record["identifier"], "result": case.get("result", "Missing"),
                                        "sourceFile": record["sourceFile"], "sourceLine": record["sourceLine"],
                                        "profile": record["profile"]})
    (output / "contract-results.json").write_text(json.dumps(dict(sorted(contracts.items())), indent=2) + "\n")
    invocations = collections.Counter()
    for node in cases:
        arguments = [child for child in nodes(node.get("children", [])) if child.get("nodeType") == "Arguments"]
        for invocation in arguments or [node]:
            invocations[invocation.get("result", "Unknown")] += 1
    coverage = capture_json(["xcrun", "xccov", "view", "--report", "--json", str(output / "Results.xcresult")],
                            output / "coverage-raw.json", output / "coverage.log")
    expected = {str(p.resolve()) for p in (ROOT / "Sieghart").rglob("*.swift") if "App" not in p.relative_to(ROOT / "Sieghart").parts}
    production_files = []
    for target in coverage.get("targets", []):
        for file in target.get("files", []):
            resolved = str(Path(file["path"]).resolve())
            if resolved in expected:
                production_files.append({**file, "path": resolved, "module": target.get("name")})
    found = {file["path"] for file in production_files}
    executable = sum(file.get("executableLines", 0) for file in production_files)
    covered = sum(file.get("coveredLines", 0) for file in production_files)
    useful_coverage = {"module": "SieghartTests", "expectedProductionFiles": len(expected),
                       "includedProductionFiles": len(found), "missingProductionFiles": sorted(expected - found),
                       "coveredLines": covered, "executableLines": executable,
                       "lineCoverage": covered / executable if executable else 0, "files": production_files}
    (output / "coverage-production.json").write_text(json.dumps(useful_coverage, indent=2) + "\n")
    changed = [name for name, digest in manifest.items()
               if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    report = {"plan": plan_name, "selectedFunctions": len(selectors), "functionResults": dict(functions),
              "invocationResults": dict(invocations), "sourceChangedDuringRun": changed,
              "missingTests": sorted(missing), "unexpectedTests": sorted(unexpected),
              "productionCoverageFiles": len(found), "expectedProductionCoverageFiles": len(expected),
              "xcodeExitCode": result.returncode}
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    if changed or expected - found or missing or unexpected or len(cases) != len(selectors):
        raise RuntimeError("Incomplete, stale or incorrectly selected evidence; see verification.json and coverage-production.json.")
    if result.returncode == 0 and (set(functions) | set(invocations)) - {"Passed"}:
        raise RuntimeError("Selected tests did not all pass; skipped/unknown results are not acceptance.")
    return result.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, RuntimeError, OSError, ValueError) as error:
        print(f"Swift Testing validation failed: {error}", file=sys.stderr)
        raise SystemExit(2)
