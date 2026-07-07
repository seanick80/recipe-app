import Foundation

/// Pure-Swift cooking unit converter (no Apple frameworks — compiles with
/// `swiftc` on Windows and is covered by the TestFixtures suite).
///
/// Converts an ingredient's quantity + unit between US/imperial and metric for
/// *display only* — callers never mutate the stored recipe. Non-measure units
/// (e.g. "egg", "clove", "to taste", "") return nil so the caller shows the
/// original value unchanged.
///
/// Conversions use precise factors, then round the result to sensible cooking
/// precision (e.g. 1 cup → 240 ml, not 236.588 ml).
enum MeasurementSystem {
    case imperial
    case metric
}

struct ConvertedMeasure: Equatable {
    let quantity: Double
    let unit: String
}

enum UnitConverter {

    /// Convert `quantity` of `unit` into the target `system`.
    /// Returns nil when `unit` isn't a recognized volume/weight measure.
    static func convert(quantity: Double, unit: String, to system: MeasurementSystem) -> ConvertedMeasure? {
        let key = normalize(unit)
        guard !key.isEmpty else { return nil }

        if let mlPerUnit = volumeToMl[key] {
            let baseMl = quantity * mlPerUnit
            switch system {
            case .metric: return metricVolume(fromMl: baseMl)
            case .imperial: return imperialVolume(fromMl: baseMl)
            }
        }
        if let gramsPerUnit = weightToG[key] {
            let baseG = quantity * gramsPerUnit
            switch system {
            case .metric: return metricWeight(fromG: baseG)
            case .imperial: return imperialWeight(fromG: baseG)
            }
        }
        return nil
    }

    // MARK: - Metric targets

    private static func metricVolume(fromMl ml: Double) -> ConvertedMeasure {
        if ml >= 1000 {
            return ConvertedMeasure(quantity: prettyRound(ml / 1000, decimals: 2), unit: "L")
        }
        return ConvertedMeasure(quantity: roundMetric(ml), unit: "ml")
    }

    private static func metricWeight(fromG g: Double) -> ConvertedMeasure {
        if g >= 1000 {
            return ConvertedMeasure(quantity: prettyRound(g / 1000, decimals: 2), unit: "kg")
        }
        return ConvertedMeasure(quantity: roundMetric(g), unit: "g")
    }

    // MARK: - Imperial targets

    private static func imperialVolume(fromMl ml: Double) -> ConvertedMeasure {
        let cup = 236.588, tbsp = 14.7868, tsp = 4.92892
        if ml >= cup * 0.75 {
            return ConvertedMeasure(quantity: prettyRound(ml / cup, decimals: 2), unit: "cup")
        }
        if ml >= tbsp {
            return ConvertedMeasure(quantity: prettyRound(ml / tbsp, decimals: 2), unit: "tbsp")
        }
        return ConvertedMeasure(quantity: prettyRound(ml / tsp, decimals: 2), unit: "tsp")
    }

    private static func imperialWeight(fromG g: Double) -> ConvertedMeasure {
        let lb = 453.592, oz = 28.3495
        if g >= lb * 0.75 {
            return ConvertedMeasure(quantity: prettyRound(g / lb, decimals: 2), unit: "lb")
        }
        return ConvertedMeasure(quantity: prettyRound(g / oz, decimals: 2), unit: "oz")
    }

    // MARK: - Rounding

    /// Round small metric amounts to readable cooking steps:
    /// <10 → nearest 1, 10–100 → nearest 5, >100 → nearest 10.
    /// (1 cup=236.6 ml → 240; 1 tbsp=14.8 → 15; 1 tsp=4.9 → 5.)
    private static func roundMetric(_ v: Double) -> Double {
        if v < 10 { return v.rounded() }
        if v < 100 { return (v / 5).rounded() * 5 }
        return (v / 10).rounded() * 10
    }

    private static func prettyRound(_ v: Double, decimals: Int) -> Double {
        let f = pow(10.0, Double(decimals))
        return (v * f).rounded() / f
    }

    // MARK: - Unit vocabulary

    private static func normalize(_ unit: String) -> String {
        unit.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
    }

    private static let volumeToMl: [String: Double] = [
        "tsp": 4.92892, "teaspoon": 4.92892, "teaspoons": 4.92892,
        "tbsp": 14.7868, "tbs": 14.7868, "tbl": 14.7868,
        "tablespoon": 14.7868, "tablespoons": 14.7868,
        "fl oz": 29.5735, "floz": 29.5735,
        "fluid ounce": 29.5735, "fluid ounces": 29.5735,
        "cup": 236.588, "cups": 236.588,
        "pint": 473.176, "pints": 473.176, "pt": 473.176,
        "quart": 946.353, "quarts": 946.353, "qt": 946.353,
        "gallon": 3785.41, "gallons": 3785.41, "gal": 3785.41,
        "ml": 1, "milliliter": 1, "milliliters": 1, "millilitre": 1, "millilitres": 1,
        "l": 1000, "liter": 1000, "liters": 1000, "litre": 1000, "litres": 1000,
    ]

    private static let weightToG: [String: Double] = [
        "oz": 28.3495, "ounce": 28.3495, "ounces": 28.3495,
        "lb": 453.592, "lbs": 453.592, "pound": 453.592, "pounds": 453.592,
        "g": 1, "gram": 1, "grams": 1, "gramme": 1, "grammes": 1,
        "kg": 1000, "kilogram": 1000, "kilograms": 1000, "kilo": 1000, "kilos": 1000,
    ]
}
