import SwiftUI

/// Where to draw the robot inside the canvas.
struct VisorLayout {
    var R: CGFloat
    var center: CGPoint
    /// y of the floor glow / shadow, nil = no floor
    var floorY: CGFloat?

    /// Robot centered horizontally in the upper part of the screen, leaving room below for a caption.
    static func watch(_ size: CGSize) -> VisorLayout {
        let R = min(size.width * 0.3, size.height * 0.24)
        let cy = size.height * 0.44
        return VisorLayout(R: R, center: CGPoint(x: size.width / 2, y: cy), floorY: cy + R * 1.22)
    }

    /// Smaller and higher, leaving the lower half for the approval buttons.
    static func watchCompact(_ size: CGSize) -> VisorLayout {
        let R = min(size.width * 0.24, size.height * 0.18)
        let cy = size.height * 0.3
        return VisorLayout(R: R, center: CGPoint(x: size.width / 2, y: cy), floorY: cy + R * 1.22)
    }

    /// Robot centered in its own canvas (iPhone), with room above for hearts and Z's.
    static func centered(_ size: CGSize) -> VisorLayout {
        let R = min(size.width * 0.28, size.height * 0.3)
        let cy = size.height * 0.5
        return VisorLayout(R: R, center: CGPoint(x: size.width / 2, y: cy), floorY: cy + R * 1.22)
    }
}

private func rgba(_ c: [Double], _ a: Double) -> Color {
    Color(.sRGB, red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255, opacity: a)
}

private func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    rgba(VisorModel.rgb(v), a)
}

private func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> Path {
    let p = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    return p.applying(CGAffineTransform(translationX: x, y: y).rotated(by: rotation))
}

/// Polygon with rounded corners (each corner gets an arc tangent to both edges).
private func roundedPoly(_ pts: [CGPoint], _ r: CGFloat) -> Path {
    var path = Path()
    let n = pts.count
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n]
        let l1 = hypot(p1.x - p0.x, p1.y - p0.y), l2 = hypot(p2.x - p1.x, p2.y - p1.y)
        let rr = min(r, l1 / 2, l2 / 2)
        if i == 0 { path.move(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)) }
        path.addArc(tangent1End: p1, tangent2End: p2, radius: rr)
    }
    path.closeSubpath()
    return path
}

private func heartPath(_ s: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: s * 0.45))
    p.addCurve(to: CGPoint(x: 0, y: -s * 0.35), control1: CGPoint(x: -s * 1.1, y: -s * 0.15), control2: CGPoint(x: -s * 0.5, y: -s * 0.95))
    p.addCurve(to: CGPoint(x: 0, y: s * 0.45), control1: CGPoint(x: s * 0.5, y: -s * 0.95), control2: CGPoint(x: s * 1.1, y: -s * 0.15))
    p.closeSubpath()
    return p
}

private func dropPath(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, top: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: x, y: y - s * top))
    p.addCurve(to: CGPoint(x: x, y: y + s), control1: CGPoint(x: x + s * 0.9, y: y - s * 0.2), control2: CGPoint(x: x + s, y: y + s))
    p.addCurve(to: CGPoint(x: x, y: y - s * top), control1: CGPoint(x: x - s, y: y + s), control2: CGPoint(x: x - s * 0.9, y: y - s * 0.2))
    p.closeSubpath()
    return p
}

private func starPath(points: Int, outer: CGFloat, inner: CGFloat, phase: CGFloat) -> Path {
    var p = Path()
    for i in 0..<(points * 2) {
        let r = i % 2 == 1 ? inner : outer
        let an = CGFloat(i) * .pi / CGFloat(points) + phase
        let pt = CGPoint(x: cos(an) * r, y: sin(an) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

extension VisorModel {
    func draw(_ g: inout GraphicsContext, layout: VisorLayout, now: Double) {
        let name = shownName, e = name.spec
        let R = layout.R, t = now - t0
        let rgb = col
        let lp = lowPower // Always On: still, dim, no glow
        let breathe = e.breathe && !lp ? sin(t * 1.8) : 0
        let float = lp ? 0 : sin(t * (e.breathe ? 0.9 : 1.6)) * 0.06 * R
        let bounce = e.bounce && !lp ? -abs(sin(t * 5.2)) * 0.07 * R : 0
        let cx = layout.center.x, cy = layout.center.y + float
        let ox = self[.ox], oy = self[.oy], roll = self[.roll]

        // floor glow + shadow (it hovers; shrinks when it rises)
        if let floorY = layout.floorY, !lp {
            let lift = (float + bounce + oy * R) / R
            let sh = 1 + lift * 0.8
            g.fill(ellipse(cx, floorY, R * 1.0 * sh, R * 0.12 * sh), with: .color(rgba(rgb, 0.10)))
            g.fill(ellipse(cx, floorY, R * 0.7 * sh, R * 0.07 * sh), with: .color(.black.opacity(0.5)))
        }

        var hg = g
        let yaw = ex * 0.5, pitch = ey * 0.45, syaw = sin(yaw), spitch = sin(pitch)
        let angry = name == .angry && !lp
        let trX = angry ? (sin(t * 53) + 0.6 * sin(t * 31)) * 0.008 * R : 0
        let trY = angry ? sin(t * 41) * 0.004 * R : (name == .sad && !lp ? sin(t * 26) * 0.0035 * R : 0)
        let wobble = name == .dizzy && !lp ? sin(t * 7) * 0.12 : 0
        hg.translateBy(x: cx + syaw * 0.04 * R + ox * R + trX, y: cy + oy * R + trY + bounce)
        hg.rotate(by: .radians(ex * 0.03 + tilt + wobble))
        let pop = self[.pop]
        hg.scaleBy(x: self[.sx] * pop * (1 - breathe * 0.012), y: self[.sy] * pop * (1 + breathe * 0.02))

        // head: wide superellipse helmet, 4-layer gloss
        let n = 2.5, k = 2 / n, rx = 1.12 * R, ry = 0.98 * R
        var head = Path()
        for i in 0...96 {
            let a = Double(i) / 96 * .pi * 2, c = cos(a), s = sin(a)
            let x = rx * (c < 0 ? -1 : 1) * pow(abs(c), k), y = ry * (s < 0 ? -1 : 1) * pow(abs(s), k)
            if i == 0 { head.move(to: CGPoint(x: x, y: y)) } else { head.addLine(to: CGPoint(x: x, y: y)) }
        }
        head.closeSubpath()
        if lp {
            hg.fill(head, with: .linearGradient(Gradient(colors: [hex(0x3A414C), hex(0x1A1E25)]),
                                                startPoint: CGPoint(x: -rx * 0.6, y: -ry), endPoint: CGPoint(x: rx * 0.7, y: ry)))
        } else {
            hg.fill(head, with: .linearGradient(Gradient(colors: [.white, hex(0xBCC6D1)]),
                                                startPoint: CGPoint(x: -rx * 0.6, y: -ry), endPoint: CGPoint(x: rx * 0.7, y: ry)))
            hg.fill(head, with: .radialGradient(Gradient(colors: [.clear, Color(.sRGB, red: 20 / 255, green: 30 / 255, blue: 45 / 255, opacity: 0.28)]),
                                                center: .zero, startRadius: R * 0.5, endRadius: R * 1.25))
            hg.fill(head, with: .linearGradient(Gradient(colors: [rgba(rgb, 0.22), rgba(rgb, 0)]),
                                                startPoint: CGPoint(x: 0, y: ry), endPoint: .zero))
            let hx = -0.45 * R - syaw * 0.28 * R, hy = -0.62 * R + spitch * 0.15 * R
            hg.fill(head, with: .radialGradient(Gradient(colors: [.white.opacity(0.95), .white.opacity(0)]),
                                                center: CGPoint(x: hx, y: hy), startRadius: 0, endRadius: 0.55 * R))

            // top shine: a soft bright band hugging the top edge + a small sharp glint
            var shine = hg
            shine.clip(to: head)
            shine.fill(ellipse(-0.1 * R - syaw * 0.22 * R, -0.62 * R + spitch * 0.1 * R, 0.78 * R, 0.26 * R, rotation: -0.08),
                       with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                              .init(color: .white.opacity(0.85), location: 0.35),
                                                              .init(color: .white.opacity(0), location: 1)]),
                                             startPoint: CGPoint(x: 0, y: -ry), endPoint: CGPoint(x: 0, y: -ry * 0.55)))
            shine.fill(ellipse(-0.62 * R - syaw * 0.25 * R, -0.58 * R + spitch * 0.1 * R, 0.1 * R, 0.05 * R, rotation: -0.6),
                       with: .color(.white.opacity(0.95)))
        }
        var cg = hg
        cg.clip(to: head)

        // visor = a band on a sphere spanning longitudes [-VA, +VA]; the roll carries it over the top
        let VA = 0.88, Rv = 1.05 * R, cr = cos(roll)
        if cr > 0.03 {
            let xl = sin(-VA + yaw) * Rv, xr = sin(VA + yaw) * Rv
            let vw = xr - xl
            let vh = 0.9 * R * (1 - 0.22 * abs(spitch)) * cr
            let vy = 0.08 * R - spitch * 0.5 * R - sin(roll) * 0.95 * R
            let rect = CGRect(x: xl, y: vy - vh / 2, width: vw, height: vh)
            let visor = Path(roundedRect: rect, cornerRadius: min(vh * 0.48, vw / 2), style: .circular)
            cg.fill(visor, with: .linearGradient(Gradient(colors: [hex(0x1A2130), hex(0x05070B)]),
                                                 startPoint: CGPoint(x: 0, y: vy - vh / 2), endPoint: CGPoint(x: 0, y: vy + vh / 2)))
            cg.stroke(visor, with: .color(.black.opacity(0.55)), lineWidth: 0.03 * R)

            var vg = cg
            vg.clip(to: visor)
            let vx = (xl + xr) / 2
            if !lp { vg.fill(Path(CGRect(x: -2 * R, y: -2 * R, width: 4 * R, height: 4 * R)),
                    with: .radialGradient(Gradient(colors: [rgba(rgb, 0.16 * self[.dim]), rgba(rgb, 0)]),
                                          center: CGPoint(x: vx, y: vy), startRadius: 0, endRadius: vw * 0.6)) }
            // eyes live on the same sphere: longitude +/-0.4 (+ a small glance inside the visor)
            let glance = ex * 0.12
            var eyeX: [Double: CGFloat] = [:]
            for sd in [-1.0, 1.0] {
                let lon = sd * 0.4 + yaw + glance
                eyeX[sd] = sin(lon) * Rv * 0.95
                let fx = max(0.45, cos(lon)) // foreshortening, never a sliver
                // vertical gaze: up = eyes rise and open wider, down = eyes sink and lids drop
                let up = max(0, ey), down = max(0, -ey)
                drawEye(&vg, x: eyeX[sd]!, y: vy - ey * 0.13 * R, sd: sd, R: R, rgb: rgb, fx: fx,
                        lidTop: down * 0.45, hScale: (1 + up * 0.14) * cr, now: now)
            }
            // tears roll down from under an eye and fade at the bottom of the visor
            if lp { return }
            for tr in tears {
                let a = now - tr.t0, kk = a / 1.4
                let tx = eyeX[tr.side]! + tr.side * 0.04 * R, ty = vy + 0.1 * R + a * a * 0.35 * R
                let s = 0.04 * R * min(1, a * 4)
                var tg = vg
                tg.opacity = kk < 0.7 ? 1 : 1 - (kk - 0.7) / 0.3
                tg.addFilter(.shadow(color: rgba(rgb, 0.9), radius: R * 0.06))
                tg.fill(dropPath(tx, ty, s, top: 1.6), with: .color(rgba(rgb, 1)))
            }
            // scanlines + a diagonal reflection
            let gap = max(1.5, R * 0.033)
            var lines = Path()
            var y = vy - vh / 2
            while y < vy + vh / 2 { lines.addRect(CGRect(x: xl, y: y, width: vw, height: gap / 3)); y += gap }
            vg.fill(lines, with: .color(.white.opacity(0.035)))
            vg.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [.init(color: .white.opacity(0), location: 0.18),
                                 .init(color: .white.opacity(0.13), location: 0.28),
                                 .init(color: .white.opacity(0), location: 0.36)]),
                startPoint: CGPoint(x: xl - syaw * 0.2 * R, y: vy - vh / 2),
                endPoint: CGPoint(x: xr - syaw * 0.2 * R, y: vy + vh / 2)))
        }

        if !lp { drawParticles(&hg, R: R, now: now) }
    }

    private func drawParticles(_ g: inout GraphicsContext, R: CGFloat, now: Double) {
        for pt in parts {
            let a = now - pt.t0
            if a < 0 { continue }
            let k = a / pt.life, alpha = k < 0.15 ? k / 0.15 : 1 - (k - 0.15) / 0.85
            let drag = pt.kind == .spark ? 1 - min(1, a * 0.6) : 1
            let sway = pt.sway.map { sin(a * 4 + $0) * 0.06 } ?? 0
            let px = (pt.x + pt.vx * a * drag + sway) * R
            let py = (pt.y + pt.vy * a * drag + 0.5 * pt.grav * a * a) * R
            var pg = g
            pg.translateBy(x: px, y: py)
            pg.opacity = max(0, alpha)
            switch pt.kind {
            case .heart:
                let s = pt.size * R * (0.8 + 0.4 * min(1, a * 3))
                pg.rotate(by: .radians(sin(a * 5 + (pt.sway ?? 0)) * 0.25))
                pg.addFilter(.shadow(color: hex(0xF472B6, 0.9), radius: R * 0.05))
                pg.fill(heartPath(s), with: .color(hex(0xF472B6)))
            case .spark:
                let s = pt.size * R * (1 - k * 0.5)
                pg.rotate(by: .radians(pt.rot + a * 3))
                pg.addFilter(.shadow(color: hex(0xC6FF3D, 0.9), radius: R * 0.05))
                pg.fill(starPath(points: 4, outer: s, inner: s * 0.28, phase: 0), with: .color(hex(0xE8FF9E)))
            case .z:
                let s = pt.size * R * (0.8 + k * 0.6)
                pg.addFilter(.shadow(color: hex(0xC4B5FD), radius: R * 0.04))
                pg.draw(Text("z").font(.system(size: s, weight: .bold, design: .rounded)).foregroundStyle(hex(0xC4B5FD)),
                        at: .zero)
            case .sweat:
                let s = pt.size * R
                pg.addFilter(.shadow(color: hex(0x7CC7FF, 0.8), radius: R * 0.03))
                pg.fill(dropPath(0, 0, s, top: 1.5), with: .color(hex(0x7CC7FF)))
            }
        }
    }

    /// One eye = one deformed shape (plus a growing glyph), composited with a glow that follows the final shape.
    private func drawEye(_ g: inout GraphicsContext, x: CGFloat, y: CGFloat, sd: Double, R: CGFloat, rgb: [Double],
                         fx: CGFloat, lidTop gazeLid: Double, hScale: Double, now: Double) {
        func clamp(_ v: Double) -> Double { max(0, min(1.15, v)) }
        let heart = clamp(self[.heart]), star = clamp(self[.star]), spiral = clamp(self[.spiral]), dots = clamp(self[.dots])
        let qmark = clamp(self[.qmark]), excl = clamp(self[.excl])
        let cw = self[.w], lidV = self[.lid], round = self[.round], slant = self[.slant], droop = self[.droop]
        let sEye = max(0, 1 - heart - star - spiral - dots - qmark - excl) // eye shrinks while a glyph grows
        let w = max(0.02 * R, cw * R) * sEye
        let h = max(0.03 * R, (sd < 0 ? self[.hL] : self[.hR]) * R * self[.open] * hScale) * sEye
        let color = rgba(rgb, 1)
        let ms = now * 1000

        let shape: (inout GraphicsContext) -> Void = { b in
            if sEye > 0.01 {
                // top edge: slant drops the inner corner, droop drops the outer corner
                let inner = -sd
                func cut(_ v: Double) -> Double { max(0, min(0.85, v)) * h }
                // the down-gaze lid yields to the happy cheek
                let lidTop = gazeLid * max(0, 1 - lidV)
                let yIn = -h / 2 + cut(slant + lidTop), yOut = -h / 2 + cut(droop + lidTop)
                let yL = inner < 0 ? yIn : yOut, yR = inner < 0 ? yOut : yIn
                let r = min(w, h) * (0.42 + 0.08 * round)
                b.fill(roundedPoly([CGPoint(x: -w / 2, y: yL), CGPoint(x: w / 2, y: yR),
                                    CGPoint(x: w / 2, y: h / 2), CGPoint(x: -w / 2, y: h / 2)], r), with: .color(color))
                // happy: a cheek rises from below and carves the eye into a ^
                let lid = max(0, min(1.1, lidV))
                if lid > 0.005 {
                    let lry = h * 0.95, top = h / 2 - lid * h * 0.72
                    var cut = b
                    cut.blendMode = .destinationOut
                    cut.fill(ellipse(0, top + lry, w * 0.78, lry), with: .color(.black))
                }
            }
            if star > 0.01 {
                let s = cw * R * 0.75 * star * (1 + 0.08 * sin(ms / 140))
                var sg = b
                sg.rotate(by: .radians(ms / 900 * sd))
                sg.fill(starPath(points: 4, outer: s, inner: s * 0.32, phase: -.pi / 2), with: .color(color))
            }
            if spiral > 0.01 {
                let s = cw * R * 0.5 * spiral
                var sg = b
                sg.rotate(by: .radians(ms / 110 * sd))
                var p = Path()
                var a = 0.0
                while a < 4.4 * .pi {
                    let r = s * 0.08 + a * s * 0.065
                    let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                    if a == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    a += 0.2
                }
                sg.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: s * 0.22, lineCap: .round, lineJoin: .round))
            }
            if excl > 0.01 {
                let s = cw * R * 0.78 * excl * (1 + 0.08 * sin(ms / 150))
                var p = Path()
                p.move(to: CGPoint(x: 0, y: -s * 0.6)); p.addLine(to: CGPoint(x: 0, y: s * 0.12))
                b.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: s * 0.36, lineCap: .round))
                b.fill(ellipse(0, s * 0.56, s * 0.18, s * 0.18), with: .color(color))
            }
            if qmark > 0.01 {
                let s = cw * R * 0.62 * qmark
                var qg = b
                qg.rotate(by: .radians(sin(ms / 320 + sd) * 0.1))
                var p = Path()
                p.addArc(center: CGPoint(x: 0, y: -s * 0.42), radius: s * 0.42,
                         startAngle: .radians(.pi * 1.08), endAngle: .radians(.pi * 2.32), clockwise: false)
                p.addQuadCurve(to: CGPoint(x: 0, y: s * 0.22), control: CGPoint(x: 0, y: -s * 0.02))
                qg.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: s * 0.3, lineCap: .round, lineJoin: .round))
                qg.fill(ellipse(0, s * 0.62, s * 0.17, s * 0.17), with: .color(color))
            }
            if dots > 0.01 {
                // three dots per eye; the pulse travels left eye -> right eye like a typing indicator
                let w0 = cw * R
                for i in 0..<3 {
                    let kk = Double(i + (sd > 0 ? 3 : 0))
                    let ph = ((ms / 1000 * 1.6 - kk * 0.11).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                    let pulse = max(0, sin(ph * .pi * 2))
                    let r = w0 * 0.15 * dots * (1 + 0.45 * pulse)
                    b.fill(ellipse((Double(i) - 1) * w0 * 0.46, -pulse * w0 * 0.06, r, r), with: .color(color))
                }
            }
            if heart > 0.01 {
                let s = cw * R * 0.62 * heart * (1 + 0.06 * sin(ms / 120))
                b.fill(heartPath(s), with: .color(color))
            }
        }

        let a = self[.dim]
        if lowPower {
            // Always On: flat, low-brightness eyes (no bloom, glow or hot core)
            var eg = g
            eg.opacity = 0.5 * a
            eg.drawLayer { l in
                l.translateBy(x: x, y: y); l.scaleBy(x: fx, y: 1)
                shape(&l)
            }
            return
        }
        // soft bloom behind, then the eye with glow, then a faint hot core
        g.fill(Path(CGRect(x: x - R * 0.5, y: y - R * 0.5, width: R, height: R)),
               with: .radialGradient(Gradient(colors: [rgba(rgb, 0.28 * a), rgba(rgb, 0)]),
                                     center: CGPoint(x: x, y: y), startRadius: 0, endRadius: R * 0.42))
        var eg = g
        eg.opacity = a
        eg.addFilter(.shadow(color: rgba(rgb, 0.95), radius: R * 0.1))
        eg.drawLayer { l in
            l.translateBy(x: x, y: y); l.scaleBy(x: fx, y: 1)
            shape(&l)
        }
        var core = g
        core.blendMode = .plusLighter
        core.opacity = 0.25 * a
        core.drawLayer { l in
            l.translateBy(x: x, y: y); l.scaleBy(x: fx, y: 1)
            shape(&l)
        }
    }
}
