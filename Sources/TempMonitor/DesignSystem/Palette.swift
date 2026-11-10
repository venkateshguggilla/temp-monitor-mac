import AppKit
import SwiftUI

/// One semantic colour in every appearance. High-contrast values are used when the
/// user turns on Accessibility → Display → Increase contrast; nil falls back.
struct Swatch: Sendable {
    let name: String
    let light: UInt32
    let dark: UInt32
    var lightHC: UInt32? = nil
    var darkHC: UInt32? = nil

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        let s = self
        return NSColor(name: NSColor.Name(name)) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            switch match {
            case .darkAqua?: return NSColor(hex: s.dark)
            case .accessibilityHighContrastDarkAqua?: return NSColor(hex: s.darkHC ?? s.dark)
            case .accessibilityHighContrastAqua?: return NSColor(hex: s.lightHC ?? s.light)
            default: return NSColor(hex: s.light)
            }
        }
    }
}

/// The palette: cool, quiet neutrals so the data carries the colour. The dark theme
/// is designed separately (lifted surfaces, desaturated hues), not inverted.
enum Palette {
    // Backgrounds and surfaces, lowest to highest elevation.
    static let backgroundPrimary = Swatch(name: "backgroundPrimary", light: 0xF4F5F7, dark: 0x15171B)
    static let backgroundSecondary = Swatch(name: "backgroundSecondary", light: 0xECEEF1, dark: 0x1B1E23)
    static let surface = Swatch(name: "surface", light: 0xFFFFFF, dark: 0x1F2228)
    static let surfaceHover = Swatch(name: "surfaceHover", light: 0xFAFBFC, dark: 0x24282F)
    static let surfacePressed = Swatch(name: "surfacePressed", light: 0xF0F2F5, dark: 0x292D35)
    static let surfaceElevated = Swatch(name: "surfaceElevated", light: 0xFFFFFF, dark: 0x2A2E36)

    // Lines.
    static let border = Swatch(name: "border", light: 0xE0E3E8, dark: 0x2E333B, lightHC: 0x868E99, darkHC: 0x7A838F)
    static let borderHover = Swatch(name: "borderHover", light: 0xC9CED6, dark: 0x3E444E, lightHC: 0x5E6670, darkHC: 0x9AA2AD)
    static let track = Swatch(name: "track", light: 0xE6E8EC, dark: 0x30353D, lightHC: 0xC4C9D0, darkHC: 0x4A515B)
    static let gridline = Swatch(name: "gridline", light: 0xE8EAEE, dark: 0x2B3037, lightHC: 0xC4C9D0, darkHC: 0x4A515B)

    // Text.
    static let textPrimary = Swatch(name: "textPrimary", light: 0x15181C, dark: 0xEDEFF2, lightHC: 0x000000, darkHC: 0xFFFFFF)
    static let textSecondary = Swatch(name: "textSecondary", light: 0x4A525C, dark: 0xB2B9C3, lightHC: 0x2E343B, darkHC: 0xD6DBE1)
    static let textTertiary = Swatch(name: "textTertiary", light: 0x5D6570, dark: 0x959DA8, lightHC: 0x3D444C, darkHC: 0xC0C6CE)

    // Interaction.
    static let accent = Swatch(name: "accent", light: 0x1F5FD6, dark: 0x78A9FF, lightHC: 0x0F48B5, darkHC: 0x9DC1FF)
    static let onAccent = Swatch(name: "onAccent", light: 0xFFFFFF, dark: 0x0B1426)
    static let focus = Swatch(name: "focus", light: 0x1F5FD6, dark: 0x8AB4FF, lightHC: 0x0F48B5, darkHC: 0xB4D0FF)
    static let selection = Swatch(name: "selection", light: 0xDDE7FB, dark: 0x233450)

    // Status. Text-safe on surfaces and on their own soft backgrounds.
    static let success = Swatch(name: "success", light: 0x13764A, dark: 0x52CC90, lightHC: 0x0B5C38, darkHC: 0x7BE0AE)
    static let warning = Swatch(name: "warning", light: 0x8F5300, dark: 0xF0B44C, lightHC: 0x6E4000, darkHC: 0xF7CB78)
    static let danger = Swatch(name: "danger", light: 0xC0262D, dark: 0xFF8077, lightHC: 0x9A1B21, darkHC: 0xFFA49D)
    static let info = Swatch(name: "info", light: 0x1F5FD6, dark: 0x78A9FF, lightHC: 0x0F48B5, darkHC: 0x9DC1FF)
    static let successSoft = Swatch(name: "successSoft", light: 0xE2F3EA, dark: 0x183427)
    static let warningSoft = Swatch(name: "warningSoft", light: 0xFBEFD9, dark: 0x382C15)
    static let dangerSoft = Swatch(name: "dangerSoft", light: 0xFCE6E5, dark: 0x40201F)
    static let neutralSoft = Swatch(name: "neutralSoft", light: 0xECEEF1, dark: 0x2A2E35)

    // Data series.
    static let seriesUsage = Swatch(name: "seriesUsage", light: 0x1F5FD6, dark: 0x78A9FF, lightHC: 0x0F48B5, darkHC: 0x9DC1FF)
    static let seriesSecondary = Swatch(name: "seriesSecondary", light: 0x7442CC, dark: 0xB396FF, lightHC: 0x5A2AB0, darkHC: 0xCBB5FF)
}

/// Semantic tokens: the only colours views use.
enum Tokens {
    static let backgroundPrimary = Palette.backgroundPrimary.color
    static let backgroundSecondary = Palette.backgroundSecondary.color
    static let surface = Palette.surface.color
    static let surfaceHover = Palette.surfaceHover.color
    static let surfacePressed = Palette.surfacePressed.color
    static let surfaceElevated = Palette.surfaceElevated.color
    static let border = Palette.border.color
    static let borderHover = Palette.borderHover.color
    static let track = Palette.track.color
    static let gridline = Palette.gridline.color
    static let textPrimary = Palette.textPrimary.color
    static let textSecondary = Palette.textSecondary.color
    static let textTertiary = Palette.textTertiary.color
    static let accent = Palette.accent.color
    static let onAccent = Palette.onAccent.color
    static let focus = Palette.focus.color
    static let selection = Palette.selection.color
    static let success = Palette.success.color
    static let warning = Palette.warning.color
    static let danger = Palette.danger.color
    static let info = Palette.info.color
    static let successSoft = Palette.successSoft.color
    static let warningSoft = Palette.warningSoft.color
    static let dangerSoft = Palette.dangerSoft.color
    static let neutralSoft = Palette.neutralSoft.color
    static let seriesUsage = Palette.seriesUsage.color
    static let seriesSecondary = Palette.seriesSecondary.color
    /// Elevation shadows; opacity is set per use. Shadows read as depth, not hue, in both themes.
    static let shadow = Color.black
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
