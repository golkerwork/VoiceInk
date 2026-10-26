import SwiftUI

enum AppTheme {
    /// Dark, minimal palette: near-black layers, hairline borders, and one violet accent.
    enum Palette {
        static let background = dynamic(light: 0xF4F4F8, dark: 0x0E0E12)
        static let sidebar = dynamic(light: 0xECECF1, dark: 0x121217)
        static let surface = dynamic(light: 0xFFFFFF, dark: 0x18181F)
        static let surfaceRaised = dynamic(light: 0xEEEEF2, dark: 0x22222C)
        static let surfaceHigh = dynamic(light: 0xE4E4EA, dark: 0x2C2C38)
        static let border = dynamic(light: 0xD4D4DC, dark: 0x2E2E3A)
        static let textSecondary = dynamic(light: 0x6B6B7B, dark: 0x9D9DAA)
        static let accent = dynamic(light: 0x6C5CE7, dark: 0x7B6CF0)
        /// Accent for text, icons and thin strokes, which need more contrast than fills.
        static let accentText = dynamic(light: 0x5A4BD1, dark: 0xA29BFE)
        static let recorder = Color(nsColor: NSColor(srgbHex: 0x101015))
        static let teal = dynamic(light: 0x00A8A3, dark: 0x00CEC9)
        static let amber = dynamic(light: 0xC9901E, dark: 0xFDCB6E)
        static let coral = dynamic(light: 0xE5484D, dark: 0xFF6B6B)

        static func dynamic(light: Int, dark: Int) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(srgbHex: isDark ? dark : light)
            })
        }
    }

    enum Accent {
        static let primary = Palette.accent
        static let fillSubtle = primary.opacity(0.10)
        static let fill = primary.opacity(0.14)
        static let fillStrong = primary.opacity(0.28)
        static let border = primary.opacity(0.40)
        static let disabled = primary.opacity(0.50)
        static let foreground = primary.opacity(0.65)
        static let strong = primary.opacity(0.80)
        static let shadow = primary.opacity(0.20)
    }

    enum Surface {
        static let card = Palette.surface
        static let materialCard = Palette.surface
        static let subtle = Color.primary.opacity(0.06)
        static let controlActive = Color.secondary.opacity(0.14)
        static let control = Color(nsColor: .controlBackgroundColor)
        static let window = Palette.background
        static let sidePanelOverlay = Palette.background.opacity(0.50)
        static let clear = Color.clear
    }

    enum Border {
        static let subtle = Palette.border
        static let card = Palette.border
        static let control = Color(nsColor: .separatorColor)
        static let tint = Color.primary.opacity(0.12)
        static let sidePanelOuter = Color.white.opacity(0.12)
    }

    enum Selection {
        static let fill = Palette.accent.opacity(0.16)
        static let border = Palette.accent.opacity(0.45)
        static let foreground = Palette.accentText
    }

    enum Status {
        static let success = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let positive = Palette.teal
        static let info = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.75)
        static let infoStrong = Palette.accentText
        static let warning = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let warningStrong = Palette.amber
        static let error = Palette.coral
    }

    enum Data {
        static let transcript = Palette.accent
        static let audio = Palette.teal
        static let enhancement = Palette.accentText
        static let purple = Palette.accentText
        static let yellow = Palette.amber
        static let orange = Color(nsColor: .systemOrange)
    }

    enum Insights {
        static let page = Palette.background
        static let card = Palette.surface
        static let elevated = Palette.surfaceRaised
        static let hover = Color.primary.opacity(0.045)
        static let border = AppTheme.Border.tint
        static let productivity = Palette.accent
        static let activity = Palette.accentText
        static let selection = productivity.opacity(0.12)
        static let selectionText = Palette.accentText
        static let grid = Color.primary.opacity(0.075)
    }

    enum Sidebar {
        static let dashboard = Color(nsColor: .systemOrange)
        static let meetings = Color(nsColor: .systemTeal)
        static let modes = Color(nsColor: .systemIndigo)
        static let models = Color(nsColor: .systemBrown)
        static let audio = Color(nsColor: .systemPink)
        static let dictionary = Color(nsColor: .systemBlue)
        static let transcribeAudio = Color(red: 0.86, green: 0.32, blue: 0.27)
        static let fallback = Color(nsColor: .systemGray)
        static let license = Color(nsColor: .systemGreen)
        static let tile = Palette.surfaceRaised
        static let tileForeground = Palette.textSecondary
        static let selectedTile = Palette.accent
    }

    enum Waveform {
        static let hoverBubble = Color.primary.opacity(0.74)
        static let hoverMarker = Color.primary.opacity(0.68)
        static let playedLower = Color.primary
        static let playedUpper = Color.primary.opacity(0.80)
        static let unplayedLower = Color.primary.opacity(0.30)
        static let unplayedUpper = Color.primary.opacity(0.20)
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let muted = secondary.opacity(0.70)
        static let disabled = Color(nsColor: .disabledControlTextColor)
        static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)
    }

    enum NativeText {
        static let primary = NSColor.labelColor
    }

    enum Action {
        static let primaryFill = Accent.primary
        static let primaryForeground = Text.onAccent
        static let destructiveFill = Palette.coral
        static let destructiveForeground = Text.onAccent
        static let secondaryForeground = Text.primary
        static let disabledFill = Surface.controlActive
        static let disabledForeground = Text.disabled
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
    }
}

extension NSColor {
    convenience init(srgbHex hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
