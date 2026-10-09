import SwiftUI

struct UtilityMeter: View {
    var value: Double
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(CompanionStyle.edge.opacity(0.12))
                .overlay(alignment: .leading) { Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * min(1, max(0, value))) }
        }.frame(height: 5).accessibilityHidden(true)
    }
}
struct UtilityTabs<Choice: Hashable>: View {
    var choices: [Choice]
    @Binding var selection: Choice
    var title: (Choice) -> String
    var body: some View {
        HStack(spacing: 18) {
            ForEach(choices, id: \.self) { choice in
                Button { selection = choice } label: {
                    Text(title(choice)).font(.callout.weight(.semibold))
                        .foregroundStyle(selection == choice ? CompanionStyle.ink : CompanionStyle.muted)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { if selection == choice { Capsule().fill(CompanionStyle.accent).frame(height: 2) } }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

struct UtilityToggle: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
        }
    }
}
