import Foundation
import SwiftData

@Observable
class RecipeViewModel {
    var searchText = ""
    var sortOrder: SortOrder = .updatedDescending

    enum SortOrder {
        case updatedDescending
        case nameAscending
        case cookTimeAscending
    }

    func generateGroceryList(from recipes: [Recipe], listName: String, context: ModelContext) -> GroceryList {
        let list = GroceryList(name: listName)

        var consolidated: [String: (quantity: Double, unit: String, category: String)] = [:]
        for recipe in recipes {
            for ingredient in recipe.ingredients {
                let key = ingredient.name.lowercased()
                if let existing = consolidated[key] {
                    consolidated[key] = (
                        quantity: existing.quantity + ingredient.quantity,
                        unit: existing.unit,
                        category: existing.category
                    )
                } else {
                    consolidated[key] = (
                        quantity: ingredient.quantity,
                        unit: ingredient.unit,
                        category: "Other"
                    )
                }
            }
        }

        for (name, info) in consolidated {
            let item = GroceryItem(
                name: name.capitalized,
                quantity: info.quantity,
                unit: info.unit,
                category: info.category
            )
            item.groceryList = list
            context.insert(item)
        }

        context.insert(list)
        return list
    }
}
