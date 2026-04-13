import AVFoundation
import Foundation
import Vision

/// Processes barcode detections from the camera feed and looks up products
/// via the Open Food Facts API.
@Observable
class BarcodeViewModel {
    var detectedBarcode: String?
    var product: ScannedProduct?
    var isLookingUp = false
    var errorMessage: String?
    var recentBarcodes: [String] = []

    /// Represents a product looked up from a barcode scan.
    struct ScannedProduct: Identifiable {
        let id = UUID()
        let barcode: String
        let name: String
        let brand: String
        let category: String
        let quantity: String
    }

    // Debounce: don't re-scan the same barcode within 3 seconds
    private var lastScanTime: Date = .distantPast
    private var lastBarcode: String = ""
    private static let debounceInterval: TimeInterval = 3

    /// Creates a VNDetectBarcodesRequest configured for UPC/EAN product barcodes.
    func makeBarcodeRequest() -> VNDetectBarcodesRequest {
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self, error == nil else { return }
            guard let results = request.results as? [VNBarcodeObservation] else { return }

            for observation in results {
                guard let payload = observation.payloadStringValue else { continue }

                // Only process product barcodes (UPC-A, UPC-E, EAN-8, EAN-13)
                let validSymbologies: [VNBarcodeSymbology] = [
                    .upce, .ean8, .ean13,
                ]
                guard validSymbologies.contains(observation.symbology) else { continue }

                Task { @MainActor in
                    self.handleDetectedBarcode(payload)
                }
                break  // Process first valid barcode only
            }
        }
        // Limit to product barcode symbologies
        request.symbologies = [.upce, .ean8, .ean13]
        return request
    }

    /// Processes a detected barcode: debounces, then triggers API lookup.
    @MainActor
    func handleDetectedBarcode(_ barcode: String) {
        let now = Date()
        if barcode == lastBarcode,
            now.timeIntervalSince(lastScanTime) < Self.debounceInterval
        {
            return
        }
        lastBarcode = barcode
        lastScanTime = now
        detectedBarcode = barcode

        if !recentBarcodes.contains(barcode) {
            recentBarcodes.append(barcode)
        }

        Task {
            await lookupProduct(barcode: barcode)
        }
    }

    /// Looks up a barcode in the Open Food Facts API.
    @MainActor
    func lookupProduct(barcode: String) async {
        isLookingUp = true
        errorMessage = nil
        product = nil

        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid barcode"
            isLookingUp = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("RecipeApp/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Product not found"
                isLookingUp = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let status = json["status"] as? Int, status == 1,
                let productDict = json["product"] as? [String: Any]
            else {
                errorMessage = "Product not found in database"
                isLookingUp = false
                return
            }

            // Extract product info using the same logic as our pure Swift mapper
            let name = bestName(from: productDict)
            let brand = productDict["brands"] as? String ?? ""
            let category = mapCategory(productDict["categories_tags"] as? [String] ?? [])
            let qty = productDict["quantity"] as? String ?? ""

            guard !name.isEmpty else {
                errorMessage = "Product has no name"
                isLookingUp = false
                return
            }

            product = ScannedProduct(
                barcode: barcode,
                name: name,
                brand: brand,
                category: category,
                quantity: qty
            )
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }

        isLookingUp = false
    }

    /// Picks best product name from OFF fields.
    private func bestName(from product: [String: Any]) -> String {
        for key in ["product_name_en", "product_name", "generic_name"] {
            if let name = product[key] as? String,
                !name.trimmingCharacters(in: .whitespaces).isEmpty
            {
                return name.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// Maps OFF category tags to store-aisle categories.
    private func mapCategory(_ tags: [String]) -> String {
        let normalized = tags.map { tag -> String in
            let parts = tag.split(separator: ":")
            return (parts.count > 1 ? String(parts[1]) : tag).lowercased()
        }

        let mapping: [(keywords: [String], category: String)] = [
            (["fruits", "vegetables", "legumes", "salads"], "Produce"),
            (["dairies", "milks", "cheeses", "yogurts", "eggs", "butters"], "Dairy"),
            (["meats", "poultry", "beef", "pork", "fish", "seafood"], "Meat"),
            (["cereals", "pasta", "rice", "canned", "sauces", "oils"], "Dry & Canned"),
            (["frozen", "ice-cream"], "Frozen"),
            (["breads", "bakery", "pastries"], "Bakery"),
            (["snacks", "chips", "crackers", "cookies", "candy"], "Snacks"),
            (["beverages", "drinks", "juices", "sodas", "waters"], "Beverages"),
            (["condiments", "dressings", "ketchup", "mustard"], "Condiments"),
            (["cleaning", "household", "paper"], "Household"),
        ]

        for tag in normalized {
            for (keywords, category) in mapping {
                for keyword in keywords {
                    if tag.contains(keyword) { return category }
                }
            }
        }
        return "Other"
    }

    func reset() {
        detectedBarcode = nil
        product = nil
        isLookingUp = false
        errorMessage = nil
    }
}
