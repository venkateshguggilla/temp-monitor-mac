# Temp Monitor design system

## Direction: a calm instrument

The chrome stays quiet and the data carries the colour. Structure is native macOS: a `NavigationSplitView` sidebar, a unified toolbar with search, a Settings scene, a menu bar extra and real menu commands. On macOS 26 the sidebar and toolbar pick up Liquid Glass from the system. The app doesn't add glass of its own, following Apple's advice to keep glass for top-level controls.

- **Status is never colour alone.** Every temperature state is an icon, a word and a colour: ✓ Normal, ⚠ Warm, 🔥 Hot, ⊖ No sensor.
- **Numbers are stable.** SF Pro Rounded with tabular digits, and `numericText` transitions, so live values don't jitter.
- **One surface per idea.** The page background, panels (hairline border, 12 pt continuous corners concentric with the window), and inset tiles. Shadows appear only on hover and on toasts.

## Tokens (`DesignSystem/Palette.swift`)

Every colour a view uses comes from `Tokens`, which resolves per appearance: Light, Dark, and both Increase Contrast variants. The dark theme is designed separately, with lifted neutral surfaces and desaturated status hues, not an inversion of the light one.

| Token | Light | Dark |
|---|---|---|
| backgroundPrimary | #F4F5F7 | #15171B |
| backgroundSecondary | #ECEEF1 | #1B1E23 |
| surface | #FFFFFF | #1F2228 |
| surfaceElevated | #FFFFFF | #2A2E36 |
| border / borderHover | #E0E3E8 / #C9CED6 | #2E333B / #3E444E |
| textPrimary / Secondary / Tertiary | #15181C / #4A525C / #5D6570 | #EDEFF2 / #B2B9C3 / #959DA8 |
| accent / focus | #1F5FD6 / #1F5FD6 | #78A9FF / #8AB4FF |
| success / warning / danger | #13764A / #8F5300 / #C0262D | #52CC90 / #F0B44C / #FF8077 |
| seriesUsage / seriesSecondary | #1F5FD6 / #7442CC | #78A9FF / #B396FF |

## Type scale (`DesignSystem/Metrics.swift`)

| Role | Font |
|---|---|
| display | 30 pt semibold, rounded, tabular |
| metric | 22 pt semibold, rounded, tabular |
| pageTitle | Title 2, semibold |
| sectionTitle | Headline |
| body / secondary | Body / Callout |
| label / metadata | Subheadline |
| mono | Callout, monospaced |

**Spacing** uses a 4 pt grid (2, 4, 8, 12, 16, 24, 32). **Radii:** panel 12, tile 8, control 6.

## Interaction states

- **Panels:** hover lifts the surface and border; press darkens and shrinks the panel to 99.5%; keyboard focus draws a 2.5 pt focus ring offset 3.5 pt (≥ 3:1 in every theme); disabled panels fade to 55%.
- **Reduce Motion:** turns off scale, shadow and slide animations; toasts fade instead of sliding.
- **Native controls** (sidebar, table, toolbar, Settings) keep their system states.
