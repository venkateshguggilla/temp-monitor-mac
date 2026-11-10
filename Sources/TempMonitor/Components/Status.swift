import SwiftUI

/// Temperature state. Always shown as icon + word + colour, never colour alone.
enum TempStatus: Int, Comparable {
    case unavailable, normal, warm, hot

    init(_ r: Reading) {
        guard let t = r.temperature else { self = .unavailable; return }
        self = t >= r.hotAt ? .hot : t >= r.warmAt ? .warm : .normal
    }

    static func < (a: TempStatus, b: TempStatus) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warm: "Warm"
        case .hot: "Hot"
        case .unavailable: "No sensor"
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warm: "exclamationmark.triangle.fill"
        case .hot: "flame.fill"
        case .unavailable: "minus.circle"
        }
    }

    var tint: Color {
        switch self {
        case .normal: Tokens.success
        case .warm: Tokens.warning
        case .hot: Tokens.danger
        case .unavailable: Tokens.textSecondary
        }
    }

    var soft: Color {
        switch self {
        case .normal: Tokens.successSoft
        case .warm: Tokens.warningSoft
        case .hot: Tokens.dangerSoft
        case .unavailable: Tokens.neutralSoft
        }
    }

    /// Colour for the temperature line in charts.
    var series: Color { self == .unavailable ? Tokens.textTertiary : tint }
}

struct StatusBadge: View {
    let status: TempStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(Typo.labelEmphasis)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(status.tint)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs + 1)
            .background(Capsule().fill(status.soft))
            .fixedSize()
            .accessibilityLabel("Status: \(status.label)")
    }
}
