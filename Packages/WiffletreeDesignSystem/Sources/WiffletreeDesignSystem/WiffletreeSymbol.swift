import SwiftUI

/// The Wiffletree symbol: the mark in the text colour with its joint in signal red, as the
/// mockups' `i-symbol` draws it on a 444 × 214 grid.
public struct WiffletreeSymbol: View {
    public init() {}

    public var body: some View {
        ZStack {
            SymbolShape(paths: SymbolShape.mark).fill(Tidal.text)
            SymbolShape(paths: SymbolShape.joint).fill(Tidal.signal)
        }
        .aspectRatio(444 / 214, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct SymbolShape: Shape {
    enum Step {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, to: CGFloat, CGFloat)
    }

    let paths: [[Step]]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 444, rect.height / 214)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        for steps in paths {
            for step in steps {
                switch step {
                case .move(let x, let y): path.move(to: point(x, y))
                case .line(let x, let y): path.addLine(to: point(x, y))
                case .curve(let cx, let cy, let x, let y): path.addQuadCurve(to: point(x, y), control: point(cx, cy))
                }
            }
            path.closeSubpath()
        }
        return path
    }

    static let mark: [[Step]] = [
        [.move(18, 0), .line(79, 0), .curve(97, 0, to: 107, 16), .line(190, 146), .curve(193, 150, to: 190, 155),
         .line(149, 201), .curve(128, 223, to: 107, 203), .line(3, 29), .curve(0, 10, to: 7, 2), .curve(11, 0, to: 18, 0)],
        [.move(277, 106), .line(324, 18), .curve(334, 0, to: 355, 0), .line(425, 0), .curve(453, 0, to: 439, 26), .line(326, 191)],
        [.move(212, 147), .line(265, 147), .line(302, 201), .curve(310, 210, to: 299, 210), .line(269, 210), .curve(248, 210, to: 239, 192)],
    ]

    static let joint: [[Step]] = [
        [.move(176, 74), .line(207, 74), .curve(220, 74, to: 229, 88), .line(265, 143), .curve(268, 147, to: 261, 147),
         .line(212, 147), .line(169, 83), .curve(165, 74, to: 176, 74)],
    ]
}
