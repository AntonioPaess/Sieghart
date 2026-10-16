"""Register Swift files in physical App/Core/Features/Shared Xcode groups."""
from pathlib import Path
import hashlib
import re

root = Path(__file__).resolve().parents[1]
source = root / "Sieghart"
project = root / "Sieghart.xcodeproj/project.pbxproj"
s = project.read_text()
refs = {m[2]: m[1] for m in re.finditer(r'^\s*(\w{24}) /\* (.*?) \*/ = \{isa = PBXFileReference;[^\n]*\};$', s, re.M)}
builds = {m[2]: m[1] for m in re.finditer(r'^\s*(\w{24}) /\* .*? \*/ = \{isa = PBXBuildFile; fileRef = (\w{24})', s, re.M)}
def ident(key): return 'B' + hashlib.sha1(key.encode()).hexdigest()[:23].upper()
files = sorted(str(p.relative_to(source)) for p in source.rglob('*.swift'))
file_ids = {}; build_ids = {}; new_refs = []; new_builds = []
for path in files:
    name = Path(path).name
    fid = refs.get(name) or ident('file:' + path)
    bid = builds.get(fid) or ident('build:' + path)
    file_ids[path] = fid; build_ids[path] = bid
    if name not in refs:
        new_refs.append(f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};')
    if fid not in builds:
        new_builds.append(f'\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};')
for path in ['Shared/Resources/ProviderAssets.xcassets', 'Shared/Resources/ModelTokenPrices.json', 'Shared/Resources/CompanionMotion-LICENSE.txt', 'Sieghart.entitlements']:
    file_ids[path] = refs[Path(path).name]
s = s.replace('/* End PBXFileReference section */', '\n'.join(new_refs) + '\n/* End PBXFileReference section */')
s = s.replace('/* End PBXBuildFile section */', '\n'.join(new_builds) + '\n/* End PBXBuildFile section */')
s = re.sub(r'(/\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \()(.*?)(\);)',
           lambda m: m[1] + '\n' + ''.join(f'\t\t\t\t{build_ids[path]} /* {Path(path).name} in Sources */,\n' for path in files) + '\t\t\t' + m[3], s, flags=re.S)
directories = set()
for path in file_ids:
    parent = Path(path).parent
    while str(parent) != '.': directories.add(str(parent)); parent = parent.parent
old = re.search(r'/\* Begin PBXGroup section \*/(.*?)/\* End PBXGroup section \*/', s, re.S)[1]
base = re.search(r'\s*A10000000000000000000002 = \{.*?\n\t\t\};', old, re.S)[0]
products = re.search(r'\s*A10000000000000000000006 /\* Products \*/ = \{.*?\n\t\t\};', old, re.S)[0]
groups = []
for directory in [''] + sorted(directories):
    gid = 'A10000000000000000000004' if not directory else ident('group:' + directory)
    name = Path(directory).name if directory else 'Sieghart'
    children = [(ident('group:' + d), Path(d).name) for d in sorted(directories) if str(Path(d).parent) == (directory or '.')]
    children += [(file_ids[f], Path(f).name) for f in sorted(file_ids) if str(Path(f).parent) == (directory or '.')]
    groups.append(f'\t\t{gid} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n' + ''.join(f'\t\t\t\t{cid} /* {label} */,\n' for cid, label in children) + f'\t\t\t);\n\t\t\tpath = {name};\n\t\t\tsourceTree = "<group>";\n\t\t}};')
s = re.sub(r'/\* Begin PBXGroup section \*/.*?/\* End PBXGroup section \*/', '/* Begin PBXGroup section */' + base + '\n' + '\n'.join(groups) + products + '\n/* End PBXGroup section */', s, flags=re.S)
project.write_text(s)
print(f'Registered {len(files)} Swift sources; preserved existing file/build references and resources.')
