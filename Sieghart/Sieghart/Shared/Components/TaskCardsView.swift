import SwiftUI

struct TaskCardsView: View {
    @ObservedObject var events: CompanionEventCenter
    var module: CompanionNotificationModule? = nil
    @State private var expanded = false
    private var cards: [CompanionTaskEvent] { events.recent.filter { module == nil || $0.module == module } }
    var body: some View {
        if !cards.isEmpty {
            DisclosureGroup("Recent activity", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(cards.prefix(5))) { event in
                        HStack(alignment: .top, spacing: 9) {
                            CompanionCharacter(size: 24, avatar: event.owner, animates: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).font(.caption.weight(.semibold))
                                Text(event.detail).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Button { events.dismissCard(event.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss \(event.title)")
                        }.padding(10).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(.top, 8)
            }.font(.caption).foregroundStyle(CompanionStyle.muted)
        }
    }
}
