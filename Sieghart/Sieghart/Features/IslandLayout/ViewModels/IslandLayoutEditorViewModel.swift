import SwiftUI

@MainActor
final class IslandLayoutEditorViewModel: ObservableObject {
    @Published var editingSlot: Int?
    @Published var dropSlot: Int?
    @Published var choosingCompanion = false
}
