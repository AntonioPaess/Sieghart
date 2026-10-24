#!/bin/bash
set -euo pipefail

app_bundle="/Applications/Sieghart.app"
tool_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --resume-keep-awake-session ) ]]; then
    echo 'Usage: launch-current-app.sh [--resume-keep-awake-session]' >&2
    exit 2
fi

[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_bundle/Contents/Info.plist")" == com.sieghart.app ]]
/bin/bash "$tool_root/Tests/verify-built-app.sh" "$app_bundle"

# LaunchServices gives this app its own privacy attribution. Running the Mach-O
# executable as a child of the development agent makes TCC inspect the parent
# app's speech purpose instead and can terminate Sieghart before permission UI.
if [[ $# -eq 1 ]]; then
    /usr/bin/open -a "$app_bundle" --args "$1"
else
    /usr/bin/open -a "$app_bundle"
fi
python3 "$tool_root/Tools/hold-awake-during-update.py" finish
