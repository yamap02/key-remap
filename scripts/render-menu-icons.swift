import CoreGraphics
import Foundation

// Vector template artwork in an 18 pt square, designed for the macOS menu bar.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Icons")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for name in ["MenuActive", "MenuPaused", "MenuAttention"] {
    var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
    let consumer = CGDataConsumer(url: destination.appendingPathComponent(name + ".pdf") as CFURL)!
    let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
    context.beginPDFPage(nil)
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.setLineWidth(1.25)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(CGPath(roundedRect: CGRect(x: 1.25, y: 2, width: 15.5, height: 14), cornerWidth: 3.25, cornerHeight: 3.25, transform: nil))
    context.strokePath()
    if name == "MenuActive" {
        context.move(to: CGPoint(x: 5, y: 11.5))
        context.addLine(to: CGPoint(x: 13, y: 11.5))
        context.move(to: CGPoint(x: 11, y: 13.5))
        context.addLines(between: [CGPoint(x: 13, y: 11.5), CGPoint(x: 11, y: 9.5)])
        context.move(to: CGPoint(x: 13, y: 6.5))
        context.addLine(to: CGPoint(x: 5, y: 6.5))
        context.move(to: CGPoint(x: 7, y: 8.5))
        context.addLines(between: [CGPoint(x: 5, y: 6.5), CGPoint(x: 7, y: 4.5)])
        context.strokePath()
    } else if name == "MenuPaused" {
        for x in [6.0, 10.0] {
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: 5.5, width: 2, height: 7), cornerWidth: 0.65, cornerHeight: 0.65, transform: nil))
            context.fillPath()
        }
    } else {
        for x in [5.5, 9, 12.5] {
            context.fillEllipse(in: CGRect(x: x - 0.85, y: 8.15, width: 1.7, height: 1.7))
        }
    }
    context.endPDFPage()
    context.closePDF()
}
