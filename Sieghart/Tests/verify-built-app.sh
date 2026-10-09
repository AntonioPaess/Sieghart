#!/bin/bash
set -euo pipefail
app_bundle="${1:?Pass the compiled Sieghart.app path}"
bundle_info="$app_bundle/Contents/Info.plist"
for privacy_key in NSAudioCaptureUsageDescription NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription NSBluetoothAlwaysUsageDescription; do
  purpose="$(/usr/bin/plutil -extract "$privacy_key" raw "$bundle_info")"
  [[ -n "$purpose" ]] || { echo "Missing built privacy purpose: $privacy_key"; exit 1; }
done
[[ "$(/usr/bin/plutil -extract LSUIElement raw "$bundle_info")" == true ]]
/usr/bin/codesign --verify --deep --strict "$app_bundle"
echo 'PASS: actual built privacy descriptions, menu-bar agent metadata and signature. App not launched.'
