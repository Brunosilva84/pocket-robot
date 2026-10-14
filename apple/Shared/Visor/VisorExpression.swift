import Foundation

/// Target look of one expression. Eye params are in units of R (head radius).
struct VisorSpec {
    var color: UInt32
    var w: Double
    var hL: Double
    var hR: Double
    var lid = 0.0, heart = 0.0, star = 0.0, spiral = 0.0, dots = 0.0, qmark = 0.0, excl = 0.0
    var round = 0.0, slant = 0.0, droop = 0.0, dim = 1.0, tilt = 0.0
    var look: (Double, Double)? = nil
    var wander = false, scan = false, bounce = false, sweat = false, zzz = false, breathe = false
    /// eyes bounce in a talking rhythm (speaking)
    var talk = false
    /// short reaction that returns to the base state afterwards
    var temp = false

    init(_ color: UInt32, w: Double, h: Double, h2: Double? = nil) {
        self.color = color; self.w = w; self.hL = h; self.hR = h2 ?? h
    }
}

enum VisorExpression: String, CaseIterable, Sendable {
    case neutral, happy, love, surprised, thinking, working, searching, question, approval
    case angry, sad, tired, sleepy, success, speaking
    // temporary reactions
    case annoyed, dizzy, yawn

    var isTemp: Bool { spec.temp }

    var spec: VisorSpec {
        var s: VisorSpec
        switch self {
        case .neutral: s = VisorSpec(0x38BDF8, w: 0.3, h: 0.34)
        case .happy: s = VisorSpec(0x4ADE80, w: 0.36, h: 0.34); s.lid = 1
        case .love: s = VisorSpec(0xF472B6, w: 0.34, h: 0.34); s.heart = 1
        case .surprised: s = VisorSpec(0xE0F2FE, w: 0.4, h: 0.44); s.round = 1
        case .thinking: s = VisorSpec(0xFBBF24, w: 0.32, h: 0.09, h2: 0.32); s.wander = true
        case .working: s = VisorSpec(0x3B9EFF, w: 0.3, h: 0.28); s.look = (0, -0.35); s.dots = 1
        case .searching: s = VisorSpec(0x818CF8, w: 0.3, h: 0.32); s.scan = true
        case .question: s = VisorSpec(0x22D3EE, w: 0.32, h: 0.38); s.tilt = 0.17; s.qmark = 1
        case .approval: s = VisorSpec(0xF5A524, w: 0.37, h: 0.42); s.round = 0.5; s.bounce = true; s.excl = 1
        case .angry: s = VisorSpec(0xEF4444, w: 0.36, h: 0.3); s.slant = 0.6
        case .sad: s = VisorSpec(0x60A5FA, w: 0.3, h: 0.28); s.droop = 0.55; s.look = (0, -0.5)
        case .tired: s = VisorSpec(0xFB923C, w: 0.32, h: 0.15); s.droop = 0.25; s.dim = 0.85; s.sweat = true
        case .sleepy: s = VisorSpec(0xA78BFA, w: 0.34, h: 0.05); s.dim = 0.55; s.zzz = true; s.breathe = true
        case .success: s = VisorSpec(0xC6FF3D, w: 0.36, h: 0.34); s.star = 1
        // happy eyes, half-carved, whose height bounces like a mouth while the reply is spoken
        case .speaking: s = VisorSpec(0x4ADE80, w: 0.36, h: 0.36); s.lid = 0.45; s.talk = true
        case .annoyed: s = VisorSpec(0xF97316, w: 0.36, h: 0.09); s.slant = 0.25; s.temp = true
        case .dizzy: s = VisorSpec(0xE879F9, w: 0.34, h: 0.34); s.spiral = 1; s.temp = true
        case .yawn: s = VisorSpec(0xA78BFA, w: 0.28, h: 0.24); s.round = 1; s.dim = 0.8; s.temp = true
        }
        return s
    }
}
