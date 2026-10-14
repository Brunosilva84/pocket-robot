import SwiftUI
import WidgetKit

/// A simplified Visor face (white helmet, black glass visor, cyan eyes) from plain shapes,
/// so the extension doesn't pull in the app's Canvas renderer.
///
/// Full color: glossy head, dark visor, glowing eyes.
/// Accented / vibrant (tinted faces, only alpha survives): a solid head silhouette with the visor
/// punched out, and the eyes in the accent group so they take the face's tint.
struct RobotFace: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ZStack {
            if renderingMode == .fullColor {
                fullColor
            } else {
                tinted
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Pocket Robot")
    }

    private var fullColor: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                HeadShape()
                    .fill(LinearGradient(colors: [.white, Palette.headShade], startPoint: .top, endPoint: .bottom))
                // top-left gloss
                Ellipse()
                    .fill(.white.opacity(0.9))
                    .frame(width: s * 0.26, height: s * 0.1)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -s * 0.24, y: -s * 0.31)
                    .blur(radius: s * 0.015)
                VisorShape()
                    .fill(LinearGradient(colors: [Palette.visorTop, Palette.visorBottom], startPoint: .top, endPoint: .bottom))
                VisorShape()
                    .stroke(.black.opacity(0.55), lineWidth: max(0.5, s * 0.012))
                EyesShape()
                    .fill(Palette.eye)
                    .shadow(color: Palette.eye.opacity(0.9), radius: s * 0.045)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tinted: some View {
        ZStack {
            HeadShape(visorCutout: true)
                .fill(.white, style: FillStyle(eoFill: true))
            EyesShape()
                .fill(.white)
                .widgetAccentable()
        }
    }
}

private enum Palette {
    static let headShade = Color(.sRGB, red: 0xBC / 255, green: 0xC6 / 255, blue: 0xD1 / 255)
    static let visorTop = Color(.sRGB, red: 0x1A / 255, green: 0x21 / 255, blue: 0x30 / 255)
    static let visorBottom = Color(.sRGB, red: 0x05 / 255, green: 0x07 / 255, blue: 0x0B / 255)
    static let eye = Color(.sRGB, red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255)
}

// Geometry, in fractions of the square the face is drawn in.
private enum Face {
    static let head = CGSize(width: 0.96, height: 0.86)
    static let headRadius = 0.4
    static let visor = CGSize(width: 0.78, height: 0.42)
    static let visorRadius = 0.2
    static let visorDY = 0.04
    static let eye = CGSize(width: 0.125, height: 0.17)
    static let eyeRadius = 0.045
    static let eyeDX = 0.175

    static func box(_ size: CGSize, in rect: CGRect, dx: Double = 0, dy: Double = 0) -> CGRect {
        let s = min(rect.width, rect.height)
        return CGRect(x: rect.midX + (dx - size.width / 2) * s,
                      y: rect.midY + (dy - size.height / 2) * s,
                      width: size.width * s, height: size.height * s)
    }

    static func visorPath(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        return Path(roundedRect: box(visor, in: rect, dy: visorDY), cornerRadius: visorRadius * s, style: .continuous)
    }
}

private struct HeadShape: Shape {
    var visorCutout = false

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        var p = Path(roundedRect: Face.box(Face.head, in: rect), cornerRadius: Face.headRadius * s, style: .continuous)
        if visorCutout {
            p.addPath(Face.visorPath(in: rect))
        }
        return p
    }
}

private struct VisorShape: Shape {
    func path(in rect: CGRect) -> Path {
        Face.visorPath(in: rect)
    }
}

private struct EyesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        var p = Path()
        for dx in [-Face.eyeDX, Face.eyeDX] {
            p.addRoundedRect(in: Face.box(Face.eye, in: rect, dx: dx, dy: Face.visorDY),
                             cornerSize: CGSize(width: Face.eyeRadius * s, height: Face.eyeRadius * s),
                             style: .continuous)
        }
        return p
    }
}
