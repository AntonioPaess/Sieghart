"""Synchronize source membership by target and path, preserving unrelated objects.

macOS plutil reads the existing OpenStep project. Only changed objects are patched.
The app, test target and test resources have independent build-file references.
"""
from pathlib import Path
import copy
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Sieghart.xcodeproj/project.pbxproj"
original = PROJECT.read_text()
project = json.loads(subprocess.check_output(
    ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(PROJECT)]))
objects = project["objects"]
before = copy.deepcopy(objects)
labels = {m[1]: m[2] for m in re.finditer(
    r"^\t\t(\w{24})(?: /\* (.*?) \*/)? = ", original, re.M) if m[2]}


def ident(key):
    return "C" + hashlib.sha1(key.encode()).hexdigest()[:23].upper()


def put(key, value, label):
    objects[key] = value
    labels[key] = label
    return key


paths, groups = {}, {}


def visit(gid, parent=""):
    obj = objects[gid]
    path = str(Path(parent) / obj.get("path", "")) if obj.get("sourceTree", "<group>") == "<group>" else obj.get("path", "")
    path = "" if path == "." else path
    if obj["isa"] == "PBXGroup":
        groups[path] = gid
        for child in obj.get("children", []):
            visit(child, path)
    elif obj["isa"] == "PBXFileReference":
        paths[path] = gid


project_object = objects[project["rootObject"]]
visit(project_object["mainGroup"])
app_id = next(k for k in project_object["targets"] if objects[k].get("name") == "Sieghart")
test_id = next((k for k in project_object["targets"] if objects[k].get("name") == "SieghartTests"),
               ident("target:SieghartTests"))
test_phases = {name: ident("phase:SieghartTests:" + name) for name in ("Sources", "Frameworks", "Resources")}
for name, phase_id in test_phases.items():
    if phase_id not in objects:
        put(phase_id, {"isa": "PBX" + name + "BuildPhase", "buildActionMask": "2147483647",
                       "files": [], "runOnlyForDeploymentPostprocessing": "0"}, name)
product_id = ident("product:SieghartTests")
put(product_id, {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle",
                 "includeInIndex": "0", "path": "SieghartTests.xctest",
                 "sourceTree": "BUILT_PRODUCTS_DIR"}, "SieghartTests.xctest")
configs = []
for config in ("Debug", "Release"):
    settings = {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.sieghart.tests",
        "SDKROOT": "macosx", "SUPPORTED_PLATFORMS": "macosx",
        "MACOSX_DEPLOYMENT_TARGET": "14.6", "SWIFT_VERSION": "6.0",
        "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "",
        "CODE_SIGN_ENTITLEMENTS": "", "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": "-", "DEVELOPMENT_TEAM": "", "ENABLE_HARDENED_RUNTIME": "NO",
        "TEST_HOST": "", "BUNDLE_LOADER": "", "ENABLE_TESTABILITY": "YES",
        "ENABLE_PREVIEWS": "NO", "SWIFT_EMIT_LOC_STRINGS": "NO",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "INFOPLIST_KEY_CFBundleDisplayName": "SieghartTests",
        "INFOPLIST_KEY_LSUIElement": "NO", "INFOPLIST_KEY_LSApplicationCategoryType": "",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@loader_path/../Frameworks",
                                  "@executable_path/../Frameworks"],
    }
    for key in ("NSAudioCaptureUsageDescription", "NSMicrophoneUsageDescription",
                "NSSpeechRecognitionUsageDescription", "NSBluetoothAlwaysUsageDescription",
                "NSCalendarsFullAccessUsageDescription", "NSAppleEventsUsageDescription"):
        settings["INFOPLIST_KEY_" + key] = ""
    if config == "Debug":
        settings["ONLY_ACTIVE_ARCH"] = "YES"
    cid = ident("config:SieghartTests:" + config)
    put(cid, {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": config}, config)
    configs.append(cid)
config_list = ident("configs:SieghartTests")
put(config_list, {"isa": "XCConfigurationList", "buildConfigurations": configs,
                  "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"},
    'Build configuration list for PBXNativeTarget "SieghartTests"')
put(test_id, {"isa": "PBXNativeTarget", "buildConfigurationList": config_list,
              "buildPhases": list(test_phases.values()), "buildRules": [], "dependencies": [],
              "name": "SieghartTests", "productName": "SieghartTests",
              "productReference": product_id, "productType": "com.apple.product-type.bundle.unit-test"},
    "SieghartTests")
if test_id not in project_object["targets"]:
    project_object["targets"].append(test_id)
products = objects[project_object["productRefGroup"]]["children"]
if product_id not in products:
    products.append(product_id)


def reference(path):
    if path in paths:
        return paths[path]
    fid = ident("file:" + path)
    filetype = {".swift": "sourcecode.swift", ".json": "text.json",
                ".xctestplan": "text"}.get(Path(path).suffix, "text")
    put(fid, {"isa": "PBXFileReference", "lastKnownFileType": filetype,
              "path": Path(path).name, "sourceTree": "<group>"}, Path(path).name)
    paths[path] = fid
    return fid


def register_tree(directory, files):
    """Manage source children without replacing other groups or resources."""
    all_dirs = {directory}
    for file in files:
        parent = Path(file).parent
        while str(parent) == directory or str(parent).startswith(directory + "/"):
            all_dirs.add(str(parent))
            parent = parent.parent
    for directory_path in sorted(all_dirs, key=lambda p: (-p.count("/"), p)):
        gid = groups.get(directory_path, ident("group:" + directory_path))
        child_dirs = sorted(d for d in all_dirs if str(Path(d).parent) == directory_path)
        child_files = sorted(f for f in files if str(Path(f).parent) == directory_path)
        children = [groups[d] for d in child_dirs] + [reference(f) for f in child_files]
        old = objects.get(gid, {})
        owned_groups = {groups.get(d) for d in all_dirs}
        for child in old.get("children", []):
            obj = objects[child]
            source_ref = obj["isa"] == "PBXFileReference" and Path(obj.get("path", "")).suffix in (".swift", ".xctestplan")
            if child not in children and not source_ref and not (obj["isa"] == "PBXGroup" and child in owned_groups):
                children.append(child)
        value = dict(old) if old else {"isa": "PBXGroup", "path": Path(directory_path).name,
                                      "sourceTree": "<group>"}
        value["children"] = children
        put(gid, value, Path(directory_path).name)
        groups[directory_path] = gid
    top = objects[project_object["mainGroup"]]["children"]
    if groups[directory] not in top:
        top.append(groups[directory])


production = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Sieghart").rglob("*.swift"))
tests = sorted(str(p.relative_to(ROOT)) for name in ("SwiftTesting", "Support")
               for p in (ROOT / "Tests" / name).rglob("*.swift"))
plans = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Tests" / "TestPlans").glob("*.xctestplan"))
register_tree("Sieghart", production)
register_tree("Tests", tests + plans)


def set_sources(target_id, files):
    target = objects[target_id]
    phase_id = next(p for p in target["buildPhases"] if objects[p]["isa"] == "PBXSourcesBuildPhase")
    phase = objects[phase_id]
    existing = {objects[bid]["fileRef"]: bid for bid in phase["files"]}
    builds = []
    for path in files:
        fid = reference(path)
        bid = existing.get(fid, ident("build:" + target_id + ":" + path))
        put(bid, {"isa": "PBXBuildFile", "fileRef": fid}, Path(path).name + " in Sources")
        builds.append(bid)
    phase["files"] = builds


set_sources(app_id, production)
unhosted = [p for p in production if not p.startswith("Sieghart/App/")]
set_sources(test_id, unhosted + tests)
price_ref = reference("Sieghart/Shared/Resources/ModelTokenPrices.json")
resource_build = ident("resource:SieghartTests:ModelTokenPrices")
put(resource_build, {"isa": "PBXBuildFile", "fileRef": price_ref}, "ModelTokenPrices.json in Resources")
resources = objects[test_phases["Resources"]]["files"]
if resource_build not in resources:
    resources.append(resource_build)


def atom(value):
    value = str(value)
    if value in labels:
        return value + " /* " + labels[value] + " */"
    if value and re.fullmatch(r"[A-Za-z0-9_./]+", value):
        return value
    return json.dumps(value, ensure_ascii=False)


def encode(value, depth):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (depth + 1) + atom(k) + " = " +
                              encode(v, depth + 1) + ";\n" for k, v in value.items()) + "\t" * depth + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (depth + 1) + encode(v, depth + 1) + ",\n" for v in value) + "\t" * depth + ")"
    return atom(value)


def entry(key):
    obj = objects[key]
    if obj["isa"] in ("PBXBuildFile", "PBXFileReference"):
        body = "{" + "".join(atom(k) + " = " + encode(v, 2) + "; " for k, v in obj.items()) + "}"
    else:
        body = encode(obj, 2)
    return "\t\t" + atom(key) + " = " + body + ";"


updated = original
new_by_section = {}
for key, obj in objects.items():
    if key in before:
        if obj == before[key]:
            continue
        pattern = r"^\t\t" + re.escape(key) + r"(?: /\*[^\n]*?\*/)? = \{[^\n]*\};|^\t\t" + re.escape(key) + r"(?: /\*[^\n]*?\*/)? = \{\n.*?^\t\t\};"
        updated, count = re.subn(pattern, lambda _: entry(key), updated, flags=re.M | re.S)
        if count != 1:
            raise RuntimeError("Could not locate existing object " + key)
    else:
        new_by_section.setdefault(obj["isa"], []).append(entry(key))
for section, entries in new_by_section.items():
    marker = "/* End " + section + " section */"
    block = "\n".join(entries) + "\n"
    if marker in updated:
        updated = updated.replace(marker, block + marker)
    else:
        section_block = "/* Begin " + section + " section */\n" + block + marker + "\n\n"
        updated = updated.replace("/* Begin PBXProject section */", section_block + "/* Begin PBXProject section */")
parsed = json.loads(subprocess.check_output(
    ["/usr/bin/plutil", "-convert", "json", "-o", "-", "-"], input=updated.encode()))
if parsed["objects"] != objects:
    raise RuntimeError("Project round-trip changed object values")
if updated != original:
    PROJECT.write_text(updated)
print(f"App: {len(production)} sources; tests: {len(unhosted)} production + {len(tests)} tests/support. Project valid.")
