import SwiftUI

/// Thin horizontal meter. Its fill meets 3:1 against the track in every theme.
struct Meter: View {
    let percent: Double?
    var tint: Color = Tokens.seriesUsage
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.track)
                Capsule().fill(tint)
                    .frame(width: max(percent ?? 0 > 0 ? height : 0, g.size.width * min(1, max(0, (percent ?? 0) / 100))))
                    .animation(Motion.standard(reduceMotion), value: percent)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Two-series history line: temperature (status colour) over usage (blue).
struct Sparkline: View {
    let card: CardState
    /// Samples to show, newest on the right.
    var samples = 120

    var body: some View {
        let status = card.status
        Canvas { ctx, size in
            for y in [0.25, 0.5, 0.75] {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height * y))
                p.addLine(to: CGPoint(x: size.width, y: size.height * y))
                ctx.stroke(p, with: .color(Tokens.gridline), lineWidth: 1)
            }
            ctx.stroke(path(Array(card.usages.suffix(samples)), size, lo: 0, hi: 100),
                       with: .color(Tokens.seriesUsage), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // Fixed band around the card's thresholds so height means the same thing over time.
            let hi = max(card.reading.hotAt + 5, card.maxTemp ?? 0)
            let lo = min(25, card.minTemp ?? 25)
            ctx.stroke(path(Array(card.temps.suffix(samples)), size, lo: lo, hi: hi),
                       with: .color(status.series), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func path(_ values: [Double?], _ size: CGSize, lo: Double, hi: Double) -> Path {
        var p = Path()
        let step = size.width / Double(samples - 1)
        let offset = samples - values.count
        var penDown = false
        for (i, v) in values.enumerated() {
            guard let v else { penDown = false; continue }
            let y = size.height - (min(hi, max(lo, v)) - lo) / (hi - lo) * (size.height - 4) - 2
            let pt = CGPoint(x: Double(offset + i) * step, y: y)
            if penDown { p.addLine(to: pt) } else { p.move(to: pt); penDown = true }
        }
        return p
    }
}

/// Legend swatch: a short line in the series colour plus its name.
struct LegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: Space.xs) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title)
        }
        .font(Typo.label)
        .foregroundStyle(Tokens.textSecondary)
    }
}

/// A big live number with its caption.
struct MetricBlock: View {
    let title: String
    let value: String
    var caption: String?
    var font: Font = Typo.display
    var alignment: HorizontalAlignment = .leading
    /// Keep two caption lines' worth of space so neighbouring panels line up.
    var reservesCaptionSpace = false

    var body: some View {
        VStack(alignment: alignment, spacing: Space.xxs) {
            Text(title)
                .font(Typo.label)
                .foregroundStyle(Tokens.textSecondary)
            Text(value)
                .font(font)
                .foregroundStyle(Tokens.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(Typo.label)
                    .foregroundStyle(Tokens.textTertiary)
                    .lineLimit(2, reservesSpace: reservesCaptionSpace)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Label / value rows in two aligned columns.
struct DetailList: View {
    let details: [Detail]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
            ForEach(details, id: \.self) { d in
                GridRow {
                    Text(d.label).foregroundStyle(Tokens.textSecondary)
                    Text(d.value).foregroundStyle(Tokens.textPrimary).monospacedDigit()
                        .textSelection(.enabled)
                }
                .font(Typo.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Surface for content groups: a quiet card with a hairline border.
struct PanelBackground: ViewModifier {
    var padding: CGFloat = Space.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Tokens.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Tokens.border))
    }
}

extension View {
    func panel(padding: CGFloat = Space.l) -> some View { modifier(PanelBackground(padding: padding)) }
}

/// Clickable panel: hover lifts the surface and border, press darkens it, and keyboard
/// focus draws a 2.5 pt ring that clears 3:1 against every background.
struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelBody(configuration: configuration)
    }

    private struct PanelBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
            configuration.label
                .padding(Space.l)
                .background(shape.fill(configuration.isPressed ? Tokens.surfacePressed : hovering ? Tokens.surfaceHover : Tokens.surface))
                .overlay(shape.strokeBorder(hovering ? Tokens.borderHover : Tokens.border))
                .overlay {
                    if focused {
                        shape.inset(by: -3.5).strokeBorder(Tokens.focus, lineWidth: 2.5)
                    }
                }
                .shadow(color: Tokens.shadow.opacity(hovering && !reduceMotion ? 0.06 : 0), radius: 8, y: 2)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.995 : 1)
                .opacity(enabled ? 1 : 0.55)
                .contentShape(shape)
                .onHover { h in withAnimation(Motion.standard(reduceMotion)) { hovering = h } }
                .animation(Motion.standard(reduceMotion), value: configuration.isPressed)
        }
    }
}

/// Toast shown at the bottom of the main window.
struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    private var tint: Color {
        switch toast.style {
        case .success: Tokens.success
        case .info: Tokens.info
        case .error: Tokens.danger
        }
    }

    private var symbol: String {
        switch toast.style {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
                .accessibilityHidden(true)
            Text(toast.message).font(Typo.body).foregroundStyle(Tokens.textPrimary)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) { action(); dismiss() }
                    .buttonStyle(.link)
                    .foregroundStyle(Tokens.accent)
            }
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.textSecondary)
                .help("Dismiss")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(Capsule(style: .continuous).fill(Tokens.surfaceElevated))
        .overlay(Capsule(style: .continuous).strokeBorder(Tokens.border))
        .shadow(color: Tokens.shadow.opacity(0.14), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}

/// Page header: title, subtitle and optional trailing content.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(Typo.pageTitle).foregroundStyle(Tokens.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(Typo.secondary).foregroundStyle(Tokens.textSecondary)
                }
            }
            Spacer(minLength: Space.m)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
