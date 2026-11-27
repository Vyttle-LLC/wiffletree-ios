import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The files on the demo's Mac that its conversations link to: Station map's layout mockup and a
/// screenshot of the map's first pass.
enum DemoFiles {
    /// The demo Mac's home folder, where `~/` references resolve.
    static let home = "/Users/demo"
    /// The tidepool checkout the Station map coordinator works in.
    static let tidepool = "/Users/demo/dev/tidepool"
    static let mockup = "\(tidepool)/design/station-page.html"
    static let screenshot = "\(tidepool)/design/station-map.png"

    static var all: [String: Data] {
        [mockup: Data(mockupHTML.utf8), screenshot: screenshotPNG]
    }

    private static let mockupHTML = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Station page</title>
        <style>
          body { font: 16px -apple-system, system-ui, sans-serif; margin: 0; color: #12303a; background: #f4f8f9; }
          header { padding: 20px; background: #0e6f8a; color: white; }
          h1 { margin: 0; font-size: 22px; }
          .map { height: 220px; margin: 16px; border-radius: 14px; background: #bfe3ec; position: relative; }
          .pin { position: absolute; width: 14px; height: 14px; border-radius: 50%; background: #e4572e; border: 2px solid white; }
          table { margin: 0 16px; width: calc(100% - 32px); border-collapse: collapse; }
          td, th { text-align: left; padding: 10px 4px; border-bottom: 1px solid #d5e4e8; }
        </style>
        </head>
        <body>
        <header><h1>Boston Harbor</h1><div>Station 8443970</div></header>
        <div class="map">
          <span class="pin" style="left: 30%; top: 40%"></span>
          <span class="pin" style="left: 55%; top: 62%"></span>
          <span class="pin" style="left: 72%; top: 30%"></span>
        </div>
        <table>
          <tr><th>Threshold</th><td>3.2 m</td></tr>
          <tr><th>Last alert</th><td>Tuesday, 06:12</td></tr>
        </table>
        </body>
        </html>
        """

    /// A drawn screenshot: sea, a coastline and the stations' pins.
    private static let screenshotPNG: Data = {
        let (width, height) = (720, 480)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(red: 0.75, green: 0.89, blue: 0.93, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.89, green: 0.92, blue: 0.84, alpha: 1)
        let coast = CGMutablePath()
        coast.move(to: CGPoint(x: 0, y: 480))
        coast.addCurve(to: CGPoint(x: 420, y: 300), control1: CGPoint(x: 160, y: 300), control2: CGPoint(x: 300, y: 380))
        coast.addCurve(to: CGPoint(x: 720, y: 360), control1: CGPoint(x: 540, y: 220), control2: CGPoint(x: 640, y: 260))
        coast.addLine(to: CGPoint(x: 720, y: 480))
        coast.closeSubpath()
        context.addPath(coast)
        context.fillPath()
        for pin in [CGPoint(x: 210, y: 300), CGPoint(x: 400, y: 190), CGPoint(x: 520, y: 330), CGPoint(x: 610, y: 150)] {
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fillEllipse(in: CGRect(x: pin.x - 13, y: pin.y - 13, width: 26, height: 26))
            context.setFillColor(red: 0.89, green: 0.34, blue: 0.18, alpha: 1)
            context.fillEllipse(in: CGRect(x: pin.x - 10, y: pin.y - 10, width: 20, height: 20))
        }
        let png = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : Data()
    }()
}
