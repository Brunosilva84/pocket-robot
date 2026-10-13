import Foundation

// Visor character engine: expression springs, colour easing, tweens (hops, squash, visor roll,
// entrance pop), blinking, gaze, temp reactions and particles. Drawing lives in VisorRenderer.swift.
// The view calls step(now:) and draw(...) once per frame from the same timeline clock.

let smoothEase: @Sendable (Double) -> Double = { t in t * t * (3 - 2 * t) }
let easeOut: @Sendable (Double) -> Double = { t in 1 - pow(1 - t, 3) }
let easeIn: @Sendable (Double) -> Double = { t in t * t }
let easeInOutCubic: @Sendable (Double) -> Double = { t in t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

enum EyeParam: Int, CaseIterable {
    case w, hL, hR, slant, droop, lid, heart, star, spiral, dots, qmark, excl, round, dim
}

enum TweenKey: Hashable {
    case open, sx, sy, ox, oy, pop, roll
}

struct Tween {
    typealias Key = (target: Double, ms: Double, ease: @Sendable (Double) -> Double)
    var keys: [Key]
    var i = 0
    var from: Double
    var start: Double
    var done: (() -> Void)?
}

struct Particle {
    enum Kind { case heart, spark, z, sweat }
    var kind: Kind
    var t0: Double
    var life: Double
    var x: Double, y: Double, vx: Double, vy: Double
    var size: Double
    var sway: Double? = nil
    var rot = 0.0
    var grav = 0.0
}

struct Tear {
    var t0: Double
    var side: Double
}

@MainActor
final class VisorModel {
    /// Seconds; defaults to wall-clock so API calls and the TimelineView date share one clock.
    var clock: () -> Double = { Date().timeIntervalSinceReferenceDate }
    var sleepAfter: Double = 14
    var blinking = true
    /// Always On (reduced luminance): ~1 Hz updates, dim look, no particles, no motion.
    var lowPower = false {
        didSet { if !lowPower { self[.open] = 1 } } // drop a half-closed AOD blink frame
    }

    private(set) var expression: VisorExpression = .neutral

    // gaze / pose
    var lookX = 0.0, lookY = 0.0
    var ex = 0.0, ey = 0.0, tilt = 0.0
    var values: [TweenKey: Double] = [.open: 1, .sx: 1, .sy: 1, .ox: 0, .oy: 0, .pop: 0, .roll: 0]

    // eye shape springs
    var cur: [Double]
    var vel: [Double]
    var col: [Double]

    // reactions
    var temp: VisorExpression?
    var tempUntil = 0.0
    var tempThen: (() -> Void)?
    var asleep = false
    var lastShown: VisorExpression?
    var tweens: [TweenKey: Tween] = [:]
    var tears: [Tear] = []
    var parts: [Particle] = []
    var slaps: [Double] = []

    var t0: Double
    var last: Double
    var lastInput: Double
    var nextBlink: Double
    var blinkAgainAt = 0.0
    var nextHuff = 0.0, nextSob = 0.0, nextHeart = 0.0, nextSpark = 0.0, nextZ = 0.0, nextSweat = 0.0
    var wanderNext = 0.0, wanderSide = 1.0
    var lastSpinAt = -10.0

    /// what the current frame shows (set by step)
    var shownName: VisorExpression = .neutral

    init(clock: (() -> Double)? = nil) {
        if let clock { self.clock = clock }
        let n = EyeParam.allCases.count
        cur = Array(repeating: 0, count: n)
        vel = Array(repeating: 0, count: n)
        cur[EyeParam.w.rawValue] = 0.3
        cur[EyeParam.hL.rawValue] = 0.34
        cur[EyeParam.hR.rawValue] = 0.34
        cur[EyeParam.dim.rawValue] = 1
        col = VisorModel.rgb(0x38BDF8)
        let now = self.clock()
        t0 = now; last = now; lastInput = now
        nextBlink = now + 1.5 + Double.random(in: 0..<2)
        greet()
    }

    subscript(_ p: EyeParam) -> Double { cur[p.rawValue] }
    subscript(_ k: TweenKey) -> Double {
        get { values[k] ?? 0 }
        set { values[k] = newValue }
    }

    nonisolated static func rgb(_ hex: UInt32) -> [Double] {
        [Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)]
    }

    // MARK: - public API

    /// Set the base state (temp reactions are ignored here; use `play`).
    func set(_ name: VisorExpression) {
        guard !name.isTemp else { return }
        expression = name
        asleep = false; temp = nil; tempThen = nil
        lastInput = clock()
    }

    /// Show a temp reaction for `seconds`, optionally chaining into `then`.
    func play(_ name: VisorExpression, seconds: Double, then: (() -> Void)? = nil) {
        temp = name
        tempUntil = clock() + seconds
        tempThen = then
    }

    func shown() -> VisorExpression { temp ?? expression }

    func greet() {
        self[.pop] = 0
        anim(.pop, [(1.08, 380, easeOut), (1, 240, smoothEase)])
        anim(.oy, [(-0.1, 160, easeOut), (0, 260, easeIn), (-0.05, 140, easeOut), (0, 200, easeIn)]) { [weak self] in
            self?.squish(0.6)
        }
        play(.happy, seconds: 1.6)
    }

    func poke() {
        let now = clock()
        lastInput = now
        if asleep { wake(); return }
        slaps = slaps.filter { now - $0 < 1.7 }
        slaps.append(now)
        if slaps.count >= 3 {
            slaps = []
            dizzy()
        } else {
            play(.annoyed, seconds: 0.8)
            anim(.ox, [(0.06, 45, easeOut), (-0.05, 60, smoothEase), (0.03, 60, smoothEase), (0, 80, easeOut)])
            squish(0.8)
        }
    }

    func dizzy() {
        play(.dizzy, seconds: 2.8)
        doRoll(turns: 2, ms: 1300)
    }

    /// Finger stroked across the robot.
    func pet() {
        lastInput = clock()
        if asleep { wake(); return }
        if temp == nil || temp == .love { play(.love, seconds: 2.4) }
    }

    /// Look toward a point; x, y normalized to -1...1 of the view (y grows downward).
    func aim(x: Double, y: Double) {
        lastInput = clock()
        if asleep { wake() }
        lookX = tanh(x * 0.704)
        lookY = -tanh(y * 0.833)
    }

    /// Finger lifted: look forward again.
    func endAim() { lookX = 0; lookY = 0 }

    /// Digital Crown spin; velocity in crown rotations per second.
    func crownSpin(velocity: Double) {
        let now = clock()
        lastInput = now
        if asleep { wake(); return }
        if abs(velocity) > 2.5 && now - lastSpinAt > 3 && temp != .dizzy {
            lastSpinAt = now
            dizzy()
        }
    }

    func wake() {
        guard asleep else { return }
        asleep = false; temp = nil; tempThen = nil
        play(.surprised, seconds: 0.7)
    }

    // MARK: - animation helpers

    func anim(_ key: TweenKey, _ keys: [Tween.Key], done: (() -> Void)? = nil) {
        tweens[key] = Tween(keys: keys, from: self[key], start: clock() * 1000, done: done)
    }

    func blink() {
        if tweens[.open] == nil { anim(.open, [(0.05, 80, easeIn), (1, 160, easeOut)]) }
    }

    /// Small volume-preserving squash on landing.
    func squish(_ k: Double = 1) {
        anim(.sy, [(1 - 0.05 * k, 70, smoothEase), (1 + 0.015 * k, 130, smoothEase), (1, 170, smoothEase)])
        anim(.sx, [(1 + 0.04 * k, 70, smoothEase), (1 - 0.012 * k, 130, smoothEase), (1, 170, smoothEase)])
    }

    /// The visor travels over the top of the head and comes back from below.
    func doRoll(turns: Double, ms: Double) {
        self[.roll] = 0
        anim(.roll, [(Double.pi * 2 * turns, ms, easeInOutCubic)]) { [weak self] in
            self?[.roll] = 0
            self?.squish(0.8)
        }
    }

    private func nod() {
        anim(.sy, [(0.97, 120, smoothEase), (1.015, 180, smoothEase), (1, 220, smoothEase)])
        anim(.sx, [(1.025, 120, smoothEase), (0.99, 180, smoothEase), (1, 220, smoothEase)])
    }

    /// What happens the moment an expression starts showing.
    private func enter(_ name: VisorExpression) {
        switch name {
        case .success:
            anim(.sy, [(0.96, 70, smoothEase), (1.02, 150, smoothEase), (1, 160, smoothEase)])
            anim(.sx, [(1.03, 70, smoothEase), (0.985, 150, smoothEase), (1, 160, smoothEase)])
            anim(.oy, [(0.015, 70, smoothEase), (-0.22, 160, easeOut), (0, 300, easeIn)]) { [weak self] in self?.squish(1) }
            for i in 0..<10 { spark(angle: Double(i) / 10 * .pi * 2, power: 1) }
            doRoll(turns: 1, ms: 950)
        case .love:
            nod()
            for i in 0..<3 { heart(delay: Double(i) * 0.15) }
        case .angry:
            nod()
            anim(.ox, [(0.07, 50, easeOut), (-0.07, 70, smoothEase), (0.05, 70, smoothEase), (-0.03, 70, smoothEase), (0, 90, easeOut)])
        case .surprised:
            anim(.oy, [(-0.1, 120, easeOut), (0, 240, easeIn)]) { [weak self] in self?.squish(0.6) }
        case .yawn:
            anim(.sy, [(1.07, 500, smoothEase), (1, 500, smoothEase)])
            anim(.sx, [(0.96, 500, smoothEase), (1, 500, smoothEase)])
        case .tired:
            nod(); sweat()
        case .sad:
            nod(); nextSob = 1 // first sob (and tear) on the next frame
        case .dizzy, .annoyed, .sleepy:
            break
        default:
            nod()
        }
    }

    private func heart(delay: Double = 0) {
        parts.append(Particle(kind: .heart, t0: clock() + delay, life: 1.8,
                              x: (rnd() - 0.5) * 0.9, y: -0.75, vx: (rnd() - 0.5) * 0.15, vy: -0.38 - rnd() * 0.14,
                              size: 0.07 + rnd() * 0.04, sway: rnd() * 6))
    }

    private func spark(angle: Double, power: Double = 0.4) {
        let sp = (0.7 + rnd() * 0.5) * power
        parts.append(Particle(kind: .spark, t0: clock(), life: 0.9 + rnd() * 0.4,
                              x: cos(angle) * 0.9, y: sin(angle) * 0.8, vx: cos(angle) * sp, vy: sin(angle) * sp,
                              size: 0.05 + rnd() * 0.04, rot: rnd() * .pi))
    }

    private func zParticle() {
        parts.append(Particle(kind: .z, t0: clock(), life: 2.2, x: 0.55 + rnd() * 0.1, y: -0.7,
                              vx: 0.18, vy: -0.32, size: 0.1 + rnd() * 0.05, sway: rnd() * 6))
    }

    private func sweat() {
        let sd: Double = rnd() < 0.5 ? -1 : 1
        parts.append(Particle(kind: .sweat, t0: clock(), life: 1.1, x: sd * 0.95, y: -0.45,
                              vx: sd * 0.12, vy: 0.15, size: 0.06, grav: 1.1))
    }

    private func rnd() -> Double { Double.random(in: 0..<1) }

    // MARK: - per-frame update

    func step(now: Double) {
        // Frames can be ~1 s apart in Always On (and longer when it resumes): integrate the springs in
        // small sub-steps over at most one second so they neither explode nor crawl.
        let span = max(0, min(1, now - last))
        let substeps = max(1, Int((span / 0.034).rounded(.up)))
        let dt = span / Double(substeps)
        last = now
        let ms = now * 1000

        for key in Array(tweens.keys) {
            guard var tw = tweens[key] else { continue }
            let (target, dur, ease) = tw.keys[tw.i]
            let p = min(1, max(0, (ms - tw.start) / dur))
            self[key] = tw.from + (target - tw.from) * ease(p)
            if p >= 1 {
                tw.from = target; tw.i += 1; tw.start = ms
                if tw.i >= tw.keys.count {
                    tweens[key] = nil
                    tw.done?()
                } else {
                    tweens[key] = tw
                }
            }
        }

        // temp reactions expire (and may chain into the next step)
        if temp != nil && now > tempUntil {
            let then = tempThen
            temp = nil; tempThen = nil
            then?()
        }
        // idle: yawn, then sleep (only from neutral)
        if !asleep && temp == nil && expression == .neutral && now - lastInput > sleepAfter {
            play(.yawn, seconds: 1.3) { [weak self] in
                self?.asleep = true
                self?.play(.sleepy, seconds: .infinity)
            }
        }

        let name = shown(), e = name.spec
        if name != lastShown {
            if lastShown != nil { enter(name) }
            lastShown = name
        }

        // eye shape springs + colour
        var tgt = [Double](repeating: 0, count: EyeParam.allCases.count)
        tgt[EyeParam.w.rawValue] = e.w
        tgt[EyeParam.hL.rawValue] = e.hL
        tgt[EyeParam.hR.rawValue] = e.hR
        if e.talk && !lowPower {
            // syllable-ish rhythm: two incommensurate beats, eyes open and close like a mouth
            let t = now - t0
            let syl = abs(sin(t * 9.0)) * (0.6 + 0.4 * abs(sin(t * 2.3)))
            tgt[EyeParam.hL.rawValue] = e.hL * (0.45 + 0.65 * syl)
            tgt[EyeParam.hR.rawValue] = e.hR * (0.45 + 0.65 * syl)
        }
        tgt[EyeParam.slant.rawValue] = e.slant
        tgt[EyeParam.droop.rawValue] = e.droop
        tgt[EyeParam.lid.rawValue] = e.lid
        tgt[EyeParam.heart.rawValue] = e.heart
        tgt[EyeParam.star.rawValue] = e.star
        tgt[EyeParam.spiral.rawValue] = e.spiral
        tgt[EyeParam.dots.rawValue] = e.dots
        tgt[EyeParam.qmark.rawValue] = e.qmark
        tgt[EyeParam.excl.rawValue] = e.excl
        tgt[EyeParam.round.rawValue] = e.round
        tgt[EyeParam.dim.rawValue] = e.dim
        let w = 2 * Double.pi / 0.5, z = 0.62
        for _ in 0..<substeps {
            for i in 0..<tgt.count {
                let acc = w * w * (tgt[i] - cur[i]) - 2 * z * w * vel[i]
                vel[i] += acc * dt
                cur[i] += vel[i] * dt
            }
        }
        let tc = VisorModel.rgb(e.color), kc = 1 - pow(0.004, span)
        for i in 0..<3 { col[i] += (tc[i] - col[i]) * kc }

        // gaze: wander (thinking), scan (searching), circles (dizzy), fixed look, or the finger
        let t = now - t0
        if e.wander && now > wanderNext {
            wanderSide = -wanderSide
            wanderNext = now + 1.5 + rnd() * 0.6
        }
        var lx = lookX, ly = lookY
        if e.wander { lx = 0.6 * wanderSide; ly = 0.5 }
        else if e.scan { lx = sin(t * 2.6) * 0.85; ly = -0.05 }
        else if name == .dizzy { lx = cos(t * 5) * 0.5; ly = sin(t * 5) * 0.35 }
        else if let look = e.look { lx = look.0; ly = look.1 }
        else if name == .sleepy { lx = 0; ly = -0.3 }
        let kl = 1 - pow(0.003, span)
        ex += (lx - ex) * kl
        ey += (ly - ey) * kl
        tilt += (e.tilt - tilt) * (1 - pow(0.01, span))

        if lowPower {
            // one half-shut frame every ~9 s reads as a slow blink at 1 Hz; no particles or tears
            tweens[.open] = nil
            self[.open] = blinking && name != .sleepy && Int(now) % 9 == 0 ? 0.3 : 1
            parts.removeAll(); tears.removeAll()
            nextBlink = now + 1 + rnd() * 2
            shownName = name
            return
        }

        if blinking && now > nextBlink && name != .sleepy {
            blink()
            if rnd() < 0.22 { blinkAgainAt = now + 0.26 }
            nextBlink = now + 2.4 + rnd() * 3
        }
        if blinkAgainAt > 0 && now > blinkAgainAt { blinkAgainAt = 0; blink() }

        // angry huffs, sad sobs (+ tears), periodic particles
        if name == .angry && now > nextHuff && tweens[.ox] == nil {
            if nextHuff > 0 {
                anim(.ox, [(0.035, 45, smoothEase), (-0.035, 60, smoothEase), (0.02, 60, smoothEase), (0, 70, smoothEase)])
            }
            nextHuff = now + 1.5 + rnd()
        }
        if name != .angry { nextHuff = 0 }
        if name == .sad && now > nextSob && tweens[.oy] == nil {
            if nextSob > 0 {
                anim(.oy, [(-0.03, 70, smoothEase), (0.008, 90, smoothEase), (-0.025, 70, smoothEase),
                           (0.006, 90, smoothEase), (-0.018, 70, smoothEase), (0, 160, smoothEase)]) { [weak self] in
                    self?.squish(0.4)
                }
                tears.append(Tear(t0: now, side: rnd() < 0.5 ? -1 : 1))
            }
            nextSob = now + 2 + rnd()
        }
        if name != .sad { nextSob = 0 }
        if name == .love && now > nextHeart { heart(); nextHeart = now + 0.45 + rnd() * 0.35 }
        if name == .success && now > nextSpark { spark(angle: rnd() * .pi * 2, power: 0.25); nextSpark = now + 0.35 + rnd() * 0.4 }
        if e.zzz && now > nextZ { zParticle(); nextZ = now + 1.1 + rnd() * 0.4 }
        if e.sweat && now > nextSweat { sweat(); nextSweat = now + 1.3 + rnd() * 0.8 }
        tears.removeAll { now - $0.t0 >= 1.4 }
        parts.removeAll { now - $0.t0 >= $0.life }

        shownName = name
    }
}
