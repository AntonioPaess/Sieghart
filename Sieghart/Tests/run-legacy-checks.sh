#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"
# Keep test fixtures in the permitted temporary workspace, independently of
# macOS per-user protected temporary directories.
mkdir -p "$check_dir/fixtures"
export TMPDIR="$check_dir/fixtures/"
source_root="Sieghart/Sieghart"
module_cache="${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}"

# Resolve feature/Core/Shared sources once. App composition is excluded so
# isolated checks never construct the resident app or start platform services.
all_sources=()
while IFS= read -r source_file; do all_sources+=("$source_file"); done < <(rg --files "$source_root" -g '*.swift' | sort | sed '/\/App\//d')
ui_shared=("$source_root/Shared/Components/DesignSystem.swift" "$source_root/Shared/Components/Island/IslandChrome.swift"
  "$source_root/Shared/Components/Companion/CompanionAvatars.swift" "$source_root/Shared/Components/Companion/CompanionArrival.swift"
  "$source_root/Shared/Models/AppearanceOptions.swift" "$source_root/Shared/Services/Preferences/CompanionPreferences.swift")
ui_shared+=("$source_root/Shared/Services/Tasks/CompanionEventCenter.swift")
while IFS= read -r shared_file; do
  case "$shared_file" in *CompanionAvatars.swift|*CompanionArrival.swift) ;; *) ui_shared+=("$shared_file");; esac
done < <(rg --files "$source_root/Shared/Components/Companion" "$source_root/Features/CompanionTeam" -g '*.swift' | sort)
codex_sources=("$source_root/Core/Services/AI/CodexUsage.swift" "$source_root/Features/AIUsage/ViewModels/CodexUsageViewModel.swift")
ai_sources=("${codex_sources[@]}" "$source_root/Core/Services/AI/ModelPricing.swift"
  "$source_root/Core/Services/AI/AIUsage.swift" "$source_root/Core/Services/AI/UsageImports.swift"
  "$source_root/Core/Services/AI/AIActivity.swift" "$source_root/Features/AIUsage/ViewModels/AIUsageViewModel.swift")
clipboard_sources=("$source_root/Core/Services/Clipboard/ClipboardHistory.swift" "$source_root/Features/Clipboard/ViewModels/ClipboardViewModel.swift")
check() {
  local check_name="$1"; shift
  if [[ -n "${SIEGHART_CHECK_FILTER:-}" && ! "$check_name" =~ $SIEGHART_CHECK_FILTER ]]; then return; fi
  xcrun swiftc -swift-version 6 -module-cache-path "$module_cache" "$@" -o "$check_dir/$check_name"
  "$check_dir/$check_name"
}

check timer "$source_root/Core/Helpers/TimerModels.swift" "$source_root/Features/Timers/ViewModels/AssistantViewModel.swift" \
  "$source_root/Core/Services/Input/SensorEngine.swift" "$source_root/Features/ImpactGestures/ViewModels/SensorViewModel.swift" Sieghart/Tests/PomodoroChecks.swift
check callbacks "$source_root/Core/Services/Voice/VoiceCapture.swift" Sieghart/Tests/VoiceCallbackChecks.swift
check voice-integration "${all_sources[@]}" Sieghart/Tests/PlatformFixtures.swift Sieghart/Tests/VoiceIntegrationChecks.swift
check interactions "${all_sources[@]}" Sieghart/Tests/PlatformFixtures.swift Sieghart/Tests/InteractionChecks.swift
check companions "${ui_shared[@]}" Sieghart/Tests/CompanionTeamChecks.swift
check usage "${codex_sources[@]}" Sieghart/Tests/CodexUsageChecks.swift
check spending "${ai_sources[@]}" Sieghart/Tests/TokenSpendingChecks.swift
check activity "${ai_sources[@]}" "${ui_shared[@]}" Sieghart/Tests/AIActivityChecks.swift
check pricing "${ai_sources[@]}" Sieghart/Tests/PricingChecks.swift
check audio "$source_root/Core/Services/Audio/AudioEngine.swift" "$source_root/Features/Audio/ViewModels/AudioViewModel.swift" Sieghart/Tests/AudioChecks.swift
check imports "${ai_sources[@]}" Sieghart/Tests/UsageImportChecks.swift
check clipboard "${clipboard_sources[@]}" "$source_root/Core/Services/Clipboard/PlainTextPaste.swift" "$source_root/Shared/Models/FileItems.swift" "${ui_shared[@]}" Sieghart/Tests/ClipboardChecks.swift
check middle-click "$source_root/Shared/Services/Input/MiddleClickController.swift" Sieghart/Tests/MiddleClickChecks.swift
check utilities "$source_root/Core/Services/System/MacSystemSampler.swift" "$source_root/Features/SystemMonitor/ViewModels/SystemMonitorViewModel.swift" \
  "$source_root/Core/Services/Power/MacAwakeBackend.swift" "$source_root/Features/KeepAwake/ViewModels/KeepAwakeViewModel.swift" \
  "$source_root/Core/Services/Display/MacDisplayPowerBackend.swift" "$source_root/Features/DisplayPower/ViewModels/DisplayPowerViewModel.swift" Sieghart/Tests/UtilityChecks.swift

check calendar "$source_root/Core/Services/Calendar/CalendarContext.swift" "$source_root/Features/Calendar/ViewModels/CalendarViewModel.swift" Sieghart/Tests/CalendarChecks.swift
check files-capture "${all_sources[@]}" Sieghart/Tests/PlatformFixtures.swift Sieghart/Tests/FileCaptureChecks.swift

check agent-room "${all_sources[@]}" Sieghart/Tests/PlatformFixtures.swift Sieghart/Tests/AgentChatMotionChecks.swift Sieghart/Tests/CodexDesktopChecks.swift Sieghart/Tests/AgentRoomChecks.swift
check local-chat "${all_sources[@]}" Sieghart/Tests/PlatformFixtures.swift Sieghart/Tests/AppleChatEligibilityChecks.swift Sieghart/Tests/AdaGitHubChecks.swift Sieghart/Tests/LocalChatChecks.swift
