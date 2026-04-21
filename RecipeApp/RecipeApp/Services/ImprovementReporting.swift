import Foundation

/// Manages the opt-in "improvement reporting" setting.
///
/// When enabled, anonymous normalization data from recipe imports is queued
/// for batch upload to the server, helping improve the import pipeline.
///
/// Privacy note: Any imported recipes that fail to import or require
/// normalization may be logged for app improvement. The user must
/// explicitly opt in via Settings.
enum ImprovementReporting {
    private static let key = "improvementReportingEnabled"

    /// Whether the user has opted in to improvement reporting.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
