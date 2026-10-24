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
        HStack {
            HStack(spacing: 3) {
                ForEach(choices, id: \.self) { choice in
                    Button { selection = choice } label: {
                        Text(LocalizedStringKey(title(choice))).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selection == choice ? CompanionStyle.ink : CompanionStyle.muted)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selection == choice ? CompanionStyle.edge.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == choice ? .isSelected : [])
                }
            }.padding(3).background(CompanionStyle.edge.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(CompanionStyle.edge.opacity(0.05), lineWidth: 0.7))
            Spacer(minLength: 0)
        }
    }

}

struct UtilityToggle: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
        }
    }
}
