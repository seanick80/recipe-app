import Foundation
import SwiftData

@Observable
class GroceryViewModel {
    func uncheckAll(in list: GroceryList) {
        for item in list.items {
            item.isChecked = false
        }
    }

    func removeChecked(in list: GroceryList, context: ModelContext) {
        let checked = list.items.filter { $0.isChecked }
        for item in checked {
            context.delete(item)
        }
    }
}
