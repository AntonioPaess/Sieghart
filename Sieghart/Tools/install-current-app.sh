#!/bin/bash
set -euo pipefail
source_bundle="${1:?Pass a verified Sieghart.app build path}"
tool_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
destination="/Applications/Sieghart.app"
info="$source_bundle/Contents/Info.plist"
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$info")" == com.sieghart.app ]]
/usr/bin/codesign --verify --deep --strict "$source_bundle"
/bin/bash "$tool_root/Tests/verify-built-app.sh" "$source_bundle"
if /usr/bin/pgrep -x Sieghart >/dev/null; then
    echo 'Quit the running Sieghart before installing. Its saved state will be retained.' >&2
    exit 1
fi
python3 "$tool_root/Tools/hold-awake-during-update.py" check
if [[ -e "$destination" ]]; then
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist")" == com.sieghart.app ]]
fi
staging="$(/usr/bin/mktemp -d /Applications/.sieghart-install.XXXXXX)"
trap '/bin/rm -rf "$staging"' EXIT
/usr/bin/ditto "$source_bundle" "$staging/Sieghart.app"
/usr/bin/codesign --verify --deep --strict "$staging/Sieghart.app"
if [[ -e "$destination" ]]; then
    backup="$(/usr/bin/mktemp -d /private/tmp/sieghart-previous-app.XXXXXX)"
    /bin/mv "$destination" "$backup/Sieghart.app"
    echo "Previous app preserved at $backup/Sieghart.app"
fi
/bin/mv "$staging/Sieghart.app" "$destination"
register='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
"$register" -u "$source_bundle" || true
# Xcode products are disposable launch targets. Leave every file intact, but
# stop offering old build paths as alternate copies of the installed app.
for old_bundle in \
    "$HOME"/Library/Developer/Xcode/DerivedData/Sieghart-*/Build/Products/Debug/Sieghart.app \
    "$HOME"/Library/Developer/Xcode/DerivedData/Sieghart-*/Build/Products/Release/Sieghart.app \
    /private/tmp/sieghart-*/Build/Products/Debug/Sieghart.app; do
    [[ -d "$old_bundle" ]] || continue
    identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$old_bundle/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$identifier" == com.sieghart.app ]]; then
        "$register" -u "$old_bundle" || true
    fi
done
"$register" -f "$destination"
echo "Installed and registered $destination"
echo 'Launch with Tools/launch-current-app.sh; never execute Contents/MacOS/Sieghart directly.'
