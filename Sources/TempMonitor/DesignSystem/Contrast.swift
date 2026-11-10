import Foundation

/// WCAG 2.2 contrast checks over the real palette values (`TempMonitor --contrast-report`).
enum Contrast {
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    struct Check {
        let fg: Swatch
        let bg: Swatch
        /// 4.5 for text, 3 for UI components and graphics (SC 1.4.3 / 1.4.11).
        let minimum: Double
        let use: String
    }

    static var checks: [Check] {
        typealias P = Palette
        var c: [Check] = []
        let textBackgrounds = [P.backgroundPrimary, P.backgroundSecondary, P.surface, P.surfaceHover,
                               P.surfacePressed, P.surfaceElevated, P.selection]
        for fg in [P.textPrimary, P.textSecondary, P.textTertiary] {
            for bg in textBackgrounds { c.append(Check(fg: fg, bg: bg, minimum: 4.5, use: "text")) }
        }
        for fg in [P.accent, P.success, P.warning, P.danger, P.info] {
            c.append(Check(fg: fg, bg: P.surface, minimum: 4.5, use: "status / link text"))
            c.append(Check(fg: fg, bg: P.backgroundPrimary, minimum: 4.5, use: "status / link text"))
        }
        c.append(Check(fg: P.success, bg: P.successSoft, minimum: 4.5, use: "badge text"))
        c.append(Check(fg: P.warning, bg: P.warningSoft, minimum: 4.5, use: "badge text"))
        c.append(Check(fg: P.danger, bg: P.dangerSoft, minimum: 4.5, use: "badge text"))
        c.append(Check(fg: P.textSecondary, bg: P.neutralSoft, minimum: 4.5, use: "badge text"))
        c.append(Check(fg: P.onAccent, bg: P.accent, minimum: 4.5, use: "text on accent"))
        for bg in [P.surface, P.backgroundPrimary, P.surfaceHover] {
            c.append(Check(fg: P.focus, bg: bg, minimum: 3, use: "focus ring"))
        }
        for fg in [P.seriesUsage, P.seriesSecondary, P.success, P.warning, P.danger] {
            c.append(Check(fg: fg, bg: P.surface, minimum: 3, use: "chart line"))
            c.append(Check(fg: fg, bg: P.track, minimum: 3, use: "meter fill vs track"))
        }
        return c
    }

    /// Markdown report for each appearance; the second value is true when every check passes.
    static func report() -> (String, Bool) {
        let modes: [(String, (Swatch) -> UInt32)] = [
            ("Light", { $0.light }), ("Dark", { $0.dark }),
            ("Light · Increase contrast", { $0.lightHC ?? $0.light }),
            ("Dark · Increase contrast", { $0.darkHC ?? $0.dark }),
        ]
        var out = "# Contrast report\n\nGenerated from `Sources/TempMonitor/DesignSystem/Palette.swift` by `TempMonitor --contrast-report`.\n"
        out += "Text needs 4.5:1 (WCAG 2.2 SC 1.4.3); focus rings, chart lines and meter fills need 3:1 (SC 1.4.11).\n"
        var allPass = true
        for (mode, pick) in modes {
            var worst = Double.infinity
            var rows = ""
            var fails = 0
            for k in checks {
                let r = ratio(pick(k.fg), pick(k.bg))
                worst = min(worst, r / k.minimum)
                let ok = r >= k.minimum
                if !ok { fails += 1; allPass = false }
                rows += "| \(k.fg.name) | \(k.bg.name) | \(k.use) | \(String(format: "%.2f", r)):1 | \(String(format: "%.1f", k.minimum)):1 | \(ok ? "Pass" : "**FAIL**") |\n"
            }
            out += "\n## \(mode): \(fails == 0 ? "all \(checks.count) checks pass" : "\(fails) failures")\n\n"
            out += "| Foreground | Background | Use | Ratio | Needs | Result |\n|---|---|---|---|---|---|\n" + rows
        }
        return (out, allPass)
    }
}
