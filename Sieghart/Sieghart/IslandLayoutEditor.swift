import SwiftUI

// The editor only changes saved layout preferences. Its miniature never starts
// a timer, opens a window or invokes the actions pictured inside the island.
struct IslandLayoutEditor: View {
    @ObservedObject var preferences: CompanionPreferences
    var onPreview: () -> Void
    @Environment(\.islandPreview) private var staticPreview
    @State private var editingSlot: Int?
    @State private var dropSlot: Int?
    @State private var choosingCompanion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dynamic Island").font(.system(size: 29, weight: .semibold, design: .rounded))
                Text("Your companion, controls and everyday tools, together at the top of your screen.")
                    .foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if staticPreview { layoutLabel }
                else {
                    Menu {
                        ForEach(IslandRailPreset.allCases) { preset in
                            Button { preferences.applyRailPreset(preset) } label: {
                                Label(preset.rawValue, systemImage: preferences.railActions == preset.actions ? "checkmark" : "circle")
                            }
                        }
                    } label: { layoutLabel }
                    .menuStyle(.borderlessButton).fixedSize().focusEffectDisabled()
                    .accessibilityLabel("Layout presets")
                }
                Button(action: onPreview) {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 16))
                        .frame(width: 42, height: 34)
                        .background(CompanionStyle.edge.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).focusEffectDisabled().help("Open the island preview")
                    .accessibilityLabel("Open the island preview")
                Spacer()
                Text("Changes save automatically").font(.caption).foregroundStyle(CompanionStyle.muted)
            }

            canvas

            Text("Click + to add a button. Drag buttons between the positions around the island. Click a button to change or remove it.")
                .font(.callout).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                Text("Size").font(.headline)
                HStack(spacing: 12) {
                    ForEach(WidgetSize.allCases) { size in
                        sizeCard(size)
                    }
                }
                Text("Expanded panels use this size. The compact island keeps the camera’s physical height.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }.companionCard()

            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(CompanionStyle.accentInk)
                    .frame(width: 38, height: 38).background(CompanionStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Liquid Glass").font(.callout.weight(.semibold))
                    Text("Optional translucent island panels.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Toggle("Liquid Glass in Dynamic Island", isOn: $preferences.islandGlass)
                    .labelsHidden().toggleStyle(WorkspaceSwitchStyle())
            }.companionCard()
        }
    }

    private var layoutLabel: some View {
        HStack(spacing: 40) {
            Text("Layout").font(.callout.weight(.medium))
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
        }.padding(.horizontal, 14).frame(height: 34)
            .background(CompanionStyle.edge.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let factor = min(1, max(0.5, (geometry.size.width - 48) / 624))
            let origin = (geometry.size.width - 624 * factor) / 2
            let top: CGFloat = 30
            ZStack(alignment: .topLeading) {
                IslandLayoutMiniature(avatar: preferences.avatar, glass: preferences.islandGlass)
                    .frame(width: 480, height: 240)
                    .scaleEffect(factor, anchor: .topLeading)
                    .frame(width: 480 * factor, height: 240 * factor)
                    .position(x: geometry.size.width / 2, y: top + 120 * factor)
                    .allowsHitTesting(false).accessibilityHidden(true)

                ForEach(0..<6) { slot in
                    slotControl(slot)
                        .position(x: origin + (slot < 3 ? 28 : 596) * factor,
                                  y: top + (52 + CGFloat(slot % 3) * 54) * factor)
                }

                Button { choosingCompanion = true } label: {
                    CompanionCharacter(size: 30, avatar: preferences.avatar, animates: false)
                        .frame(width: 44, height: 44).background(.black, in: Circle())
                        .environment(\.colorScheme, .dark)
                }.buttonStyle(IslandButtonStyle()).focusEffectDisabled()
                    .help("Change your companion").accessibilityLabel("Change your companion: \(preferences.avatar.name)")
                    .popover(isPresented: $choosingCompanion) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose your companion").font(.headline)
                            CompanionAvatarPicker(selection: $preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, compact: true)
                        }.padding(20).frame(width: 480)
                            .environment(\.surfaceGlassEnabled, preferences.windowGlass)
                    }
                    .position(x: geometry.size.width / 2, y: top + 240 * factor + 32)
            }
        }
        .frame(height: 352)
        .background(CompanionStyle.edge.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func slotControl(_ slot: Int) -> some View {
        let action = preferences.railActions[slot]
        // Native drag/drop hosting is absent in an ImageRenderer. Draw the
        // same control directly for offscreen previews; runtime keeps it live.
        if staticPreview { IslandEditorSlot(action: action, avatar: preferences.avatar, active: false, edit: {}) }
        else if action == .none { slotButton(slot, action: action) }
        else { slotButton(slot, action: action).draggable("sieghart.rail.\(slot)") }
    }

    private func slotButton(_ slot: Int, action: IslandRailAction) -> some View {
        IslandEditorSlot(action: action, avatar: preferences.avatar, active: editingSlot == slot || dropSlot == slot) { editingSlot = slot }
            .accessibilityLabel("\(Self.positionLabel(slot)): \(action == .none ? "Add button" : action.rawValue)")
            .accessibilityHint("Click to edit. Drag a button here to move it.")
            .popover(isPresented: Binding(get: { editingSlot == slot }, set: { if !$0 { editingSlot = nil } }), arrowEdge: slot < 3 ? .trailing : .leading) {
                actionPicker(slot)
            }
            .dropDestination(for: String.self) { items, _ in
                guard items.count == 1, let value = items.first, value.hasPrefix("sieghart.rail."),
                      let source = Int(value.dropFirst("sieghart.rail.".count)), (0..<6).contains(source), source != slot,
                      preferences.railActions[source] != .none else { return false }
                preferences.moveRail(from: source, to: slot); editingSlot = nil; dropSlot = nil; return true
            } isTargeted: { targeted in
                if targeted { dropSlot = slot }
                else if dropSlot == slot { dropSlot = nil }
            }
    }

    private func actionPicker(_ slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.positionLabel(slot)).font(.headline).padding(.horizontal, 10).padding(.vertical, 8)
            ForEach(IslandRailAction.allCases.filter { $0 != .none }) { action in
                Button {
                    preferences.setRail(action, at: slot); editingSlot = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol).frame(width: 20).foregroundStyle(CompanionStyle.accentInk)
                        Text(action.rawValue)
                        Spacer()
                        if preferences.railActions[slot] == action { Image(systemName: "checkmark").foregroundStyle(CompanionStyle.accentInk) }
                    }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).focusEffectDisabled()
            }
            if preferences.railActions[slot] != .none {
                Divider().padding(.vertical, 4)
                Button {
                    preferences.setRail(.none, at: slot); editingSlot = nil
                } label: { Label("Remove button", systemImage: "minus.circle").padding(10) }
                    .buttonStyle(.plain).focusEffectDisabled()
            }
        }.padding(10).frame(width: 230)
    }

    private func sizeCard(_ size: WidgetSize) -> some View {
        let selected = preferences.widgetSize == size
        return Button { preferences.widgetSize = size } label: {
            VStack(spacing: 14) {
                Image(systemName: size == .small ? "arrow.down.and.line.horizontal.and.arrow.up" : size == .large ? "arrow.up.left.and.arrow.down.right" : "arrow.left.and.right")
                    .font(.system(size: 25, weight: .medium)).frame(height: 32)
                Text(size.rawValue).font(.callout.weight(.semibold))
            }.foregroundStyle(selected ? CompanionStyle.accentInk : CompanionStyle.muted)
                .frame(maxWidth: .infinity).frame(height: 106)
                .background(selected ? CompanionStyle.accent.opacity(0.10) : CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? CompanionStyle.accent.opacity(0.8) : .clear, lineWidth: 1.5) }
        }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("\(size.rawValue) widget")
            .accessibilityValue(selected ? "Selected" : "")
    }

    private static func positionLabel(_ slot: Int) -> String {
        "\(slot < 3 ? "Left" : "Right") · \(["Top", "Middle", "Bottom"][slot % 3])"
    }
}

private struct IslandEditorSlot: View {
    var action: IslandRailAction
    var avatar: CompanionAvatar
    var active: Bool
    var edit: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: edit) {
            ZStack {
                Circle().fill(action == .none ? Color.clear : .black)
                if action == .none {
                    Circle().strokeBorder(CompanionStyle.accentInk.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(CompanionStyle.accentInk)
                } else if action == .companion || action == .avatars {
                    CompanionCharacter(size: 28, avatar: avatar, animates: false).environment(\.colorScheme, .dark)
                } else {
                    Image(systemName: action.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                }
                if active || hovering {
                    Circle().strokeBorder(CompanionStyle.accentInk, lineWidth: 1.5)
                }
            }.frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).focusEffectDisabled().onHover { hovering = $0 }
            .help(action == .none ? "Add button" : "Edit \(action.rawValue)")
    }
}

private struct IslandLayoutMiniature: View {
    var avatar: CompanionAvatar
    var glass: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text("Companion").font(.system(size: 20, weight: .semibold))
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 16))
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            HStack(spacing: 24) {
                CompanionCharacter(size: 78, avatar: avatar, animates: false).frame(width: 94, height: 84)
                VStack(alignment: .leading, spacing: 9) {
                    Text("YOUR COMPANION").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.white.opacity(0.5))
                    Text("Ready when you are.").font(.system(size: 17, weight: .semibold))
                    Text("A little company for your day.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 42).padding(.top, 26).padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .background { IslandBackdrop(compact: false, stripHeight: 0, glassEnabled: glass).environment(\.islandPreview, true).environment(\.colorScheme, .dark) }
            .clipShape(NotchPanelShape())
            .environment(\.colorScheme, .dark)
    }
}
