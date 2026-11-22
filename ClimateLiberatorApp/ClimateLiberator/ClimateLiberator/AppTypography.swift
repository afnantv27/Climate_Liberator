import SwiftUI

/// The app's type scale. One family (SF Pro), semibold for emphasis, monospaced
/// digits wherever figures are compared.
///
/// Capitalization: Title Case for screen and card titles, buttons, tabs, segmented
/// controls and menu items; sentence case for descriptions, field labels, toggles,
/// status text and tooltips.
extension Font {
    /// Launch screen and the main dashboard heading.
    static let appDisplay = Font.system(size: 34, weight: .bold)
    /// Heading at the top of each workspace screen.
    static let appPageTitle = Font.system(size: 28, weight: .bold)
    /// Title of a card or panel.
    static let appSectionTitle = Font.title3.weight(.semibold)
    /// Large figure in a metric card.
    static let appMetric = Font.system(size: 26, weight: .semibold).monospacedDigit()
}
