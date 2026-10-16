import SwiftUI

struct CompanionMotionStudio: View {
    @StateObject private var model: CompanionMotionStudioViewModel
    @Environment(\.dismiss) private var dismiss
    var animates = true
    var close: (() -> Void)? = nil
    init(initialMember: CompanionAvatar = .sig, animates: Bool = true, close: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: CompanionMotionStudioViewModel(member: initialMember))
        self.animates = animates; self.close = close
    }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Meet your team").font(.title2.weight(.semibold))
                    Text("Sig leads. Every specialist has a character of their own.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Button("Done") { if let close { close() } else { dismiss() } }.buttonStyle(CompanionButtonStyle(compact: true))
            }
            HStack(spacing: 6) {
                ForEach(CompanionAvatar.allCases) { member in
                    Button { model.member = member; model.play() } label: {
                        VStack(spacing: 3) {
                            CompanionCharacter(size: 40, avatar: member, animates: false)
                            Text(member.name).font(.caption.weight(.medium))
                        }.frame(maxWidth: .infinity).padding(7).modifier(WorkspaceSurface(selected: model.member == member, radius: 14))
                    }.buttonStyle(.plain).focusEffectDisabled()
                }
            }
            CompanionCharacter(size: 224, avatar: model.member, animates: animates, animation: model.animation, replay: model.replay)
                .frame(maxWidth: .infinity).background(CompanionStyle.edge.opacity(0.025), in: RoundedRectangle(cornerRadius: 22))
            VStack(spacing: 4) {
                Text(model.member.subtitle).font(.headline)
                Text(model.member.detail).font(.callout).foregroundStyle(CompanionStyle.muted)
            }
            HStack {
                Picker("Movement", selection: $model.animation) {
                    ForEach(CompanionAnimation.allCases) { movement in Text(movement.title).tag(movement) }
                }.onChange(of: model.animation) { _, _ in model.play() }
                Button("Replay") { model.play() }.buttonStyle(CompanionButtonStyle(primary: true, compact: true))
            }
            Text("A movement preview. File transfers and specialist integrations will be connected as their tools become available.")
                .font(.caption).foregroundStyle(CompanionStyle.muted).multilineTextAlignment(.center)
        }.padding(24).frame(width: 560).foregroundStyle(CompanionStyle.ink).background(CompanionStyle.background)
    }
}
