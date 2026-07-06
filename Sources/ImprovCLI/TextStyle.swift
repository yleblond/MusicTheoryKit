import Foundation

/// ANSI styling for the `watch` screen's textual status block — bold/colored field labels
/// distinct from their (plain) values, bold headings for section titles, so the eye can
/// scan the screen quickly instead of parsing a wall of same-colored text.
enum TextStyle {
    static let reset = "\u{1B}[0m"
    static let label = "\u{1B}[1;34m"    // bold blue
    static let heading = "\u{1B}[1;3;37m" // bold italic white
    static let good = "\u{1B}[1;32m"     // bold green: true/active states
    static let dim = "\u{1B}[2m"         // faint: false/inactive states, placeholders

    /// "Label: value", with the label bold-colored and the value left in the default
    /// foreground so the two are unmistakably different at a glance.
    static func field(_ label: String, _ value: String) -> String {
        "\(TextStyle.label)\(label):\(TextStyle.reset) \(value)"
    }

    static func heading(_ text: String) -> String {
        "\(TextStyle.heading)\(text)\(TextStyle.reset)"
    }

    /// Bold green when true, faint when false — booleans read at a glance instead of
    /// needing to parse the word.
    static func flag(_ value: Bool) -> String {
        value ? "\(TextStyle.good)true\(TextStyle.reset)" : "\(TextStyle.dim)false\(TextStyle.reset)"
    }

    static func placeholder(_ text: String) -> String {
        "\(TextStyle.dim)\(text)\(TextStyle.reset)"
    }
}
