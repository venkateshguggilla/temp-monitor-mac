import SwiftUI

/// Type scale. SF Pro throughout; SF Pro Rounded with tabular digits for live numbers
/// so values don't jitter as they change.
enum Typo {
    static let display = Font.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
    static let metric = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    static let pageTitle = Font.title2.weight(.semibold)
    static let sectionTitle = Font.headline
    static let body = Font.body
    static let secondary = Font.callout
    static let label = Font.subheadline
    static let labelEmphasis = Font.subheadline.weight(.semibold)
    static let metadata = Font.subheadline.monospacedDigit()
    static let mono = Font.system(.callout, design: .monospaced)
}

/// 4-pt spacing grid.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    /// Panels sit inside macOS 26's rounder windows; 12 keeps corners concentric.
    static let panel: CGFloat = 12
    static let tile: CGFloat = 8
    static let control: CGFloat = 6
}

/// Motion that respects Reduce Motion.
enum Motion {
    static func standard(_ reduce: Bool) -> Animation? { reduce ? nil : .snappy(duration: 0.25) }
    static func gentle(_ reduce: Bool) -> Animation? { reduce ? .linear(duration: 0.01) : .spring(duration: 0.35, bounce: 0.15) }
}
