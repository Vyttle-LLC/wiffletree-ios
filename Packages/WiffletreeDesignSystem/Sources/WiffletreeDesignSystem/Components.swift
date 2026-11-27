import SwiftUI

/// A status colour with its tint. Status is never colour alone: every use pairs it with a glyph
/// and words.
public enum Tone: Sendable {
    case accent, green, cyan, yellow, red, focus, subtle

    public var color: Color {
        switch self {
        case .accent: Tidal.accent
        case .green: Tidal.green
        case .cyan: Tidal.cyan
        case .yellow: Tidal.yellow
        case .red: Tidal.red
        case .focus: Tidal.focus
        case .subtle: Tidal.subtle
        }
    }

    public var tint: Color {
        switch self {
        case .accent: Tidal.tintAccent
        case .green: Tidal.tintGreen
        case .cyan: Tidal.tintCyan
        case .yellow: Tidal.tintYellow
        case .red: Tidal.tintRed
        case .focus: Tidal.tintFocus
        case .subtle: Tidal.overlay
        }
    }
}

/// A state in words with its glyph, such as "On Wi-Fi".
public struct StatusLabel: View {
    private let text: String
    private let systemImage: String
    private let tone: Tone

    public init(_ text: String, systemImage: String, tone: Tone) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.tight)
            .font(.subheadline)
            .foregroundStyle(tone.color)
    }
}

/// A rounded tag on the tone's tint, such as a ticket's state.
public struct Chip: View {
    private let text: String
    private let systemImage: String?
    private let tone: Tone

    public init(_ text: String, systemImage: String? = nil, tone: Tone) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .foregroundStyle(tone.color)
        .background(tone.tint, in: .capsule)
    }
}

/// A count of what needs the human, filled yellow as the mockups draw it.
public struct CountBadge: View {
    private let count: Int
    private let fill: Color

    public init(_ count: Int, fill: Color = Tidal.yellow) {
        self.count = count
        self.fill = fill
    }

    public var body: some View {
        Text(count, format: .number)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Tidal.onAccent)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(fill, in: .capsule)
            .accessibilityLabel("\(count) need you")
    }
}

/// The demo host's marker: a small outlined tag in the focus teal. It informs; it does not warn.
public struct DemoTag: View {
    public enum Size: Sendable { case regular, small }
    private let size: Size

    public init(size: Size = .regular) {
        self.size = size
    }

    public var body: some View {
        Text("Demo")
            .textCase(.uppercase)
            .font(.system(size: size == .regular ? 12 : 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Tidal.cyan)
            .padding(.horizontal, size == .regular ? 8 : 5)
            .padding(.vertical, size == .regular ? 2 : 1)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tidal.cyan, lineWidth: 1))
    }
}

/// A square glyph tile leading a list row.
public struct IconTile: View {
    private let systemImage: String
    private let fill: Color?
    private let size: CGFloat

    /// With no fill, the tile is the overlay grey with text-coloured glyph.
    public init(_ systemImage: String, fill: Color? = nil, size: CGFloat = 30) {
        self.systemImage = systemImage
        self.fill = fill
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55))
            .foregroundStyle(fill == nil ? Tidal.text : Tidal.onAccent)
            .frame(width: size, height: size)
            .background(fill ?? Tidal.overlay, in: .rect(cornerRadius: size * 0.24))
    }
}

/// The large round art above an explainer's title.
public struct ExplainerArt: View {
    private let systemImage: String
    private let tone: Tone

    public init(_ systemImage: String, tone: Tone = .cyan) {
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 40))
            .foregroundStyle(tone.color)
            .frame(width: 76, height: 76)
            .background(tone.tint, in: .rect(cornerRadius: 20))
    }
}

extension View {
    /// A card: the surface with the mockups' padding and corner.
    public func card() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tidal.surface, in: .rect(cornerRadius: 14))
    }
}

/// An inset grouped list on the Tidal base, its rows on the surface. A row background must be
/// set on the rows, which a modifier on `List` doesn't reach, so the list wraps its content.
public struct TidalList<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        List {
            Group { content }
                .listRowBackground(Tidal.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Tidal.base)
    }
}

/// A full-width button as the mockups draw them: filled, tinted, grey or plain.
public struct TidalButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case filled, tinted, gray, plain }
    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(foreground)
            .background(background, in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .filled: Tidal.onAccent
        case .tinted, .plain: Tidal.accent
        case .gray: Tidal.text
        }
    }

    private var background: Color {
        switch kind {
        case .filled: Tidal.accent
        case .tinted: Tidal.tintAccent
        case .gray: Tidal.overlay
        case .plain: .clear
        }
    }
}

extension ButtonStyle where Self == TidalButtonStyle {
    public static func tidal(_ kind: TidalButtonStyle.Kind) -> TidalButtonStyle {
        TidalButtonStyle(kind)
    }
}

/// A label with its glyph close to the words, as status lines use.
public struct TightLabelStyle: LabelStyle {
    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

extension LabelStyle where Self == TightLabelStyle {
    public static var tight: TightLabelStyle { TightLabelStyle() }
}
