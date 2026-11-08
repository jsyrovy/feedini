import SwiftUI

/// The order of the story list, in the toolbar and the View menu.
struct ListOrderPicker: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Picker("Sort", selection: $preferences.listOrder) {
            ForEach(ListOrder.allCases, id: \.self) { order in
                Text(order.title)
            }
        }
    }
}

extension ListOrder {
    var title: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }
}
