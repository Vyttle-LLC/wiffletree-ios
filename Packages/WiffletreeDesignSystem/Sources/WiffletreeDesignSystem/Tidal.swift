import SwiftUI
import UIKit

/// The Tidal theme, as the host's `design/themes/wiffletree-tidal.json` and the mockups'
/// `styles.css` define it. Each token has a light and a dark value; tints wash a status colour
/// into the surface the way the mockups' `color-mix` does.
public enum Tidal {
    // MARK: Brand, the same in both appearances

    public static let deepTeal = Color(hex: 0x1A262D)
    public static let blueTeal = Color(hex: 0x1C3742)
    public static let tide = Color(hex: 0x2D5A5A)
    public static let paper = Color(hex: 0xF3F2ED)
    /// The logo joint only.
    public static let signal = Color(hex: 0xD63C35)

    // MARK: Surfaces and text

    public static let base = Color(Palette.base)
    public static let surface = Color(Palette.surface)
    public static let overlay = Color(Palette.overlay)
    public static let text = Color(Palette.text)
    public static let subtle = Color(Palette.subtle)
    public static let muted = Color(Palette.muted)
    public static let edge = Color(Palette.edge)

    // MARK: Accent and states

    public static let accent = Color(Palette.accent)
    public static let onAccent = Color(Palette.onAccent)
    public static let focus = Color(Palette.focus)
    public static let green = Color(Palette.green)
    public static let red = Color(Palette.red)
    public static let yellow = Color(Palette.yellow)
    public static let blue = Color(Palette.blue)
    public static let magenta = Color(Palette.magenta)
    public static let cyan = Color(Palette.cyan)

    // MARK: Tints, for chips, soft buttons and the demo strip

    public static let tintAccent = Color(Palette.mix(Palette.accent, 0.10, into: Palette.surface))
    public static let tintYellow = Color(Palette.mix(Palette.yellow, 0.14, into: Palette.surface))
    public static let tintGreen = Color(Palette.mix(Palette.green, 0.14, into: Palette.surface))
    public static let tintRed = Color(Palette.mix(Palette.red, 0.13, into: Palette.surface))
    public static let tintCyan = Color(Palette.mix(Palette.cyan, 0.14, into: Palette.surface))
}

/// The tokens as UIKit colours that resolve per appearance.
enum Palette {
    static let base = dynamic(light: 0xF3F2ED, dark: 0x1A262D)
    static let surface = dynamic(light: 0xFFFDF7, dark: 0x22373E)
    static let overlay = dynamic(light: 0xE4E9E3, dark: 0x2A434A)
    static let text = dynamic(light: 0x1A262D, dark: 0xF3F2ED)
    static let subtle = dynamic(light: 0x526865, dark: 0xAFBFBC)
    static let muted = dynamic(light: 0x748781, dark: 0x829B99)
    static let edge = dynamic(light: 0xC4CFCA, dark: 0x496063)
    static let accent = dynamic(light: 0x902818, dark: 0xE6977E)
    static let onAccent = dynamic(light: 0xFFFDF7, dark: 0x1A262D)
    static let focus = dynamic(light: 0x2D5A5A, dark: 0x86C1BC)
    static let green = dynamic(light: 0x326348, dark: 0xA0CBB0)
    static let red = dynamic(light: 0xA3213E, dark: 0xFFA6B8)
    static let yellow = dynamic(light: 0x77551C, dark: 0xE4C17A)
    static let blue = dynamic(light: 0x365E78, dark: 0x9AC4D8)
    static let magenta = dynamic(light: 0x765074, dark: 0xCFADD0)
    static let cyan = dynamic(light: 0x2D5A5A, dark: 0x86C1BC)

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    /// `color-mix(in srgb, color share, base)`, resolved in each appearance.
    static func mix(_ color: UIColor, _ share: CGFloat, into base: UIColor) -> UIColor {
        UIColor { traits in
            var top: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var bottom: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            color.resolvedColor(with: traits).getRed(&top.0, green: &top.1, blue: &top.2, alpha: &top.3)
            base.resolvedColor(with: traits).getRed(&bottom.0, green: &bottom.1, blue: &bottom.2, alpha: &bottom.3)
            return UIColor(
                red: top.0 * share + bottom.0 * (1 - share),
                green: top.1 * share + bottom.1 * (1 - share),
                blue: top.2 * share + bottom.2 * (1 - share),
                alpha: 1
            )
        }
    }
}

extension Color {
    /// Opaque sRGB from a 24-bit value, such as `0x1A262D`.
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
