#!/bin/bash
set -euo pipefail
app_bundle="${1:?Pass the compiled Sieghart.app path}"
bundle_info="$app_bundle/Contents/Info.plist"
for privacy_key in NSAudioCaptureUsageDescription NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription NSBluetoothAlwaysUsageDescription NSCalendarsFullAccessUsageDescription; do
  purpose="$(/usr/bin/plutil -extract "$privacy_key" raw "$bundle_info")"
  [[ -n "$purpose" ]] || { echo "Missing built privacy purpose: $privacy_key"; exit 1; }
done
[[ "$(/usr/bin/plutil -extract LSUIElement raw "$bundle_info")" == true ]]
/usr/bin/codesign --verify --deep --strict "$app_bundle"
entitlements="$(/usr/bin/codesign -d --entitlements :- "$app_bundle" 2>/dev/null)"
[[ "$entitlements" == *'<key>com.apple.security.personal-information.calendars</key><true/>'* ]] || {
  echo 'Missing signed Calendar capability'; exit 1;
}
echo 'PASS: actual built privacy descriptions, menu-bar agent metadata and signature. App not launched.'
