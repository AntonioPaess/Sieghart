import AppKit
import SwiftUI

@MainActor
final class CompanionPreferences: ObservableObject {
    @Published private(set) var railActions: [IslandRailAction]
    @Published private(set) var toolActions: [IslandToolAction]
    func setTool(_ action: IslandToolAction, at slot: Int) {
        guard action != .avatars, toolActions.indices.contains(slot) else { return }
        var next = toolActions
        if let other = next.firstIndex(of: action), other != slot { next.swapAt(other, slot) }
        else { next[slot] = action }
        toolActions = next
        defaults.set(next.map(\.rawValue), forKey: "island.tools")
    }
    func resetTools() {
        toolActions = IslandToolAction.defaultSelection
        defaults.set(toolActions.map(\.rawValue), forKey: "island.tools")
    }
    func moveTool(from source: Int, to destination: Int) {
        guard toolActions.indices.contains(source), toolActions.indices.contains(destination), source != destination else { return }
        var next = toolActions
        next.swapAt(source, destination)
        toolActions = next
        defaults.set(next.map(\.rawValue), forKey: "island.tools")
    }
    func setRail(_ action: IslandRailAction, at slot: Int) {
        guard railActions.indices.contains(slot) else { return }
        var next = railActions
        if action != .none, let other = next.firstIndex(of: action), other != slot { next[other] = next[slot] }
        next[slot] = action; railActions = next; defaults.set(next.map(\.rawValue), forKey: "island.rails")
    }
    func applyRailPreset(_ preset: IslandRailPreset) {
        railActions = preset.actions; defaults.set(railActions.map(\.rawValue), forKey: "island.rails")
    }
    func moveRail(from source: Int, to destination: Int) {
        guard railActions.indices.contains(source), railActions.indices.contains(destination), source != destination,
              railActions[source] != .none else { return }
        setRail(railActions[source], at: destination)
    }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance.theme") } }
    @Published var windowGlass: Bool { didSet { save(windowGlass, "windowGlass") } }
    @Published var islandGlass: Bool { didSet { save(islandGlass, "islandGlass") } }
    @Published var hoverEnabled: Bool { didSet { save(hoverEnabled, "hover") } }
    @Published var impactsEnabled: Bool { didSet { save(impactsEnabled, "impacts") } }
    @Published var compactTimer: Bool { didSet { save(compactTimer, "compactTimer") } }
    @Published var launchGreeting: Bool { didSet { save(launchGreeting, "launchGreeting") } }
    @Published var introductionLanguage: CompanionIntroductionLanguage { didSet { defaults.set(introductionLanguage.rawValue, forKey: "appearance.introductionLanguage") } }
    @Published var characterMotion: Bool { didSet { save(characterMotion, "characterMotion") } }
    @Published var reduceMotion: Bool { didSet { save(reduceMotion, "reduceMotion") } }
    @Published var widgetSize: WidgetSize { didSet { defaults.set(widgetSize.rawValue, forKey: "appearance.widgetSize") } }
    var avatar: CompanionAvatar { .sig }
    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: "onboarding.completed.v1") } }
    private let defaults: UserDefaults
    var featureDefaults: UserDefaults { defaults }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedRails = defaults.stringArray(forKey: "island.rails")?.compactMap { IslandRailAction(rawValue: $0 == "Avatars" ? "Team" : $0) }
        railActions = savedRails?.count == 6 ? savedRails!.map { $0 == .avatars ? .companion : $0 } : IslandRailPreset.essentials.actions
        let savedTools = defaults.stringArray(forKey: "island.tools")?.compactMap { IslandToolAction(rawValue: $0 == "Avatars" ? "Team" : $0) }
        var migratedTools = savedTools ?? IslandToolAction.defaultSelection
        if let legacy = migratedTools.firstIndex(of: .avatars) {
            migratedTools[legacy] = [.files, .capture, .downloads].first { !migratedTools.contains($0) } ?? .files
        }
        let validTools = migratedTools.count == 10 && Set(migratedTools).count == 10 ? migratedTools : IslandToolAction.defaultSelection
        toolActions = validTools
        defaults.set(validTools.map(\.rawValue), forKey: "island.tools")
        appearance = defaults.string(forKey: "appearance.theme").flatMap(AppAppearance.init(rawValue:)) ?? .system
        windowGlass = defaults.object(forKey: "appearance.windowGlass") as? Bool ?? false
        islandGlass = defaults.object(forKey: "appearance.islandGlass") as? Bool ?? false
        widgetSize = defaults.string(forKey: "appearance.widgetSize").flatMap(WidgetSize.init(rawValue:)) ?? .medium
        onboardingComplete = defaults.bool(forKey: "onboarding.completed.v1")
        hoverEnabled = defaults.object(forKey: "appearance.hover") as? Bool ?? true
        impactsEnabled = defaults.object(forKey: "appearance.impacts") as? Bool ?? false
        compactTimer = defaults.object(forKey: "appearance.compactTimer") as? Bool ?? true
        launchGreeting = defaults.object(forKey: "appearance.launchGreeting") as? Bool ?? true
        introductionLanguage = defaults.string(forKey: "appearance.introductionLanguage").flatMap(CompanionIntroductionLanguage.init(rawValue:)) ?? .english
        characterMotion = defaults.object(forKey: "appearance.characterMotion") as? Bool ?? true
        reduceMotion = defaults.object(forKey: "appearance.reduceMotion") as? Bool ?? false
        defaults.set(CompanionAvatar.sig.rawValue, forKey: "appearance.avatar")
    }

    var usesReducedMotion: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func save(_ value: Bool, _ name: String) { defaults.set(value, forKey: "appearance.\(name)") }
}
