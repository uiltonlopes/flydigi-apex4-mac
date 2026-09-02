// ForceAdapt (adaptive trigger) modes exactly as Space Station 4 offers them for the Apex 4 (k2), with the
// same labels, parameters and ranges. Reference: SS4's `SetForceTriggerCommandFactory` (live command),
// `SaveTriggerAdapterConfig` (profile blob) and the renderer's trigger tab (labels, min/max).
//
// Note the naming trap in SS4: its enum value `Sniper` (type 2) is *labelled* "Recoil" (机枪, machine gun) in
// the UI and its enum value `Recoil` (type 3) is labelled "Sniper" (狙击). We use the UI names (SS4's English
// locale); the byte values are the enum's.
//
// "Output data starting from the start position" (SS4's MatchStart / matchStroke byte): when on, the trigger
// reports a full press as soon as it reaches the effect's start position — the travel before it is the whole
// 0–100 % range, the effect zone is "past the floor". SS4 always sends it on for Racing (and zeroes it when
// the start is 0, because that would mean 100 % all the time); for Recoil/Sniper it is a checkbox, off by default.

import SwiftUI
import FlydigiKit
import FlydigiTransport

struct ForceAdapt: Codable, Hashable {
    enum Mode: Int, Codable, CaseIterable, Hashable {
        case normal = 0, race = 1, recoil = 2, sniper = 3, lock = 4, vibration = 5
    }
    var mode: Mode = .normal
    /// Race / machine gun / sniper: trigger travel where the effect starts (0…192). Lock: lock position
    /// (20…200). Vibration: stroke over which it vibrates (1…200).
    var start = 60
    /// Race: damping force (1…255). Machine gun: force needed to start vibrating (1…255). Sniper: breakthrough
    /// stroke (1…255).
    var level = 128
    /// Machine gun: vibration strength (1…255). Sniper: breakthrough resistance (1…255). Vibration: strength
    /// coefficient (0…200).
    var strength = 128
    /// Machine gun / vibration: vibration frequency (1…255).
    var frequency = 100
    /// Vibration only: grip-rumble values below this do not move the trigger (1…255).
    var block = 50
    /// "Output data starting from the start position" (SS4's MatchStart): full press reported at the start
    /// position. Racing: on in SS4 (hidden). Recoil / sniper: checkbox, off by default.
    var outputFromStart = false

    static let labels: [(Mode, String)] = [(.normal, "General"), (.race, "Racing"), (.recoil, "Recoil"), (.sniper, "Sniper"), (.lock, "Trigger lock"), (.vibration, "Vibration")]

    /// Starting point for a mode. Space Station has no per-mode defaults of its own (a freshly picked mode
    /// starts from whatever the profile held, zeros included); these are sensible mid-range values, the
    /// vibration ones taken from the Apex 4 factory profile (block 10, scale 50, frequency 90).
    static func defaults(for mode: Mode) -> ForceAdapt {
        var c = ForceAdapt(); c.mode = mode
        switch mode {
        case .normal: break
        // Racing reports 100 % at the damping start (see header), so the start sits near the end of the travel.
        case .race: c.start = 150; c.level = 128; c.outputFromStart = true
        case .recoil: c.start = 60; c.level = 128; c.strength = 128; c.frequency = 100; c.outputFromStart = false
        case .sniper: c.start = 90; c.level = 60; c.strength = 150; c.outputFromStart = false
        case .lock: c.start = 100
        case .vibration: c.strength = 50; c.block = 10; c.start = 100; c.frequency = 90
        }
        return c
    }
    var isDefault: Bool { self == ForceAdapt.defaults(for: mode) }
    static func label(_ m: Mode) -> String { labels.first { $0.0 == m }?.1 ?? "Normal" }
    var isNormal: Bool { mode == .normal }

    // Tolerant decoding so rules saved by older builds (stroke/pressure/matchStroke fields) still load.
    private enum Keys: String, CodingKey { case mode, start, level, strength, frequency, block, outputFromStart }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        mode = Mode(rawValue: (try? c.decode(Int.self, forKey: .mode)) ?? 0) ?? .normal
        start = (try? c.decode(Int.self, forKey: .start)) ?? 60
        level = (try? c.decode(Int.self, forKey: .level)) ?? 128
        strength = (try? c.decode(Int.self, forKey: .strength)) ?? 128
        frequency = (try? c.decode(Int.self, forKey: .frequency)) ?? 100
        block = (try? c.decode(Int.self, forKey: .block)) ?? 50
        outputFromStart = (try? c.decode(Bool.self, forKey: .outputFromStart)) ?? (mode == .race)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(mode.rawValue, forKey: .mode); try c.encode(start, forKey: .start); try c.encode(level, forKey: .level)
        try c.encode(strength, forKey: .strength); try c.encode(frequency, forKey: .frequency); try c.encode(block, forKey: .block)
        try c.encode(outputFromStart, forKey: .outputFromStart)
    }

    // MARK: Bytes

    private func b(_ v: Int, min lo: Int = 0, max hi: Int = 255) -> UInt8 { UInt8(clamping: Swift.min(hi, Swift.max(lo, v))) }

    /// Parameters after the side byte for the live command (`A5 30 06 <apply> <side> …`; mode 5 is turned
    /// into `A5 30 08` by `DeviceSession.setForceTriggerRaw`). Same bytes SS4 sends.
    var liveParams: [UInt8] {
        switch mode {
        case .normal: return [0]
        case .race: return [1, b(start, max: 192), b(level, min: 1), (outputFromStart && start > 0) ? 1 : 0]   // SS4 zeroes match at start 0
        case .recoil: return [2, b(start, max: 192), b(level, min: 1), b(strength, min: 1), b(frequency, min: 1), outputFromStart ? 1 : 0]
        case .sniper: return [3, b(start, max: 192), b(level, min: 1), b(strength, min: 1), 0, outputFromStart ? 1 : 0]
        case .lock: return [4, b(start, min: 20, max: 200), 255, 1]
        case .vibration: return [5, b(block, min: 1), b(strength, max: 200), b(start, min: 1, max: 200), b(frequency, min: 1)]
        }
    }

    /// The 20-byte adapter block of a trigger in the profile blob (type, bind type, filter, scale, 5 bind
    /// params, mixed border, 10 params), following SS4's `SaveTriggerAdapterConfig` + `ParseTriggerConfigToArray`.
    func adapterBlock(previous: [UInt8]) -> [UInt8] {
        var p = [UInt8](repeating: 0xFF, count: 20)
        if previous.count >= 20 { p[2] = previous[2]; p[3] = previous[3]; for i in 4..<10 { p[i] = previous[i] } }
        p[0] = UInt8(mode.rawValue); p[1] = mode == .vibration ? 2 : 0
        var params: [UInt8]
        switch mode {
        case .normal: params = [previous.count >= 20 ? previous[10] : 0, previous.count >= 20 ? previous[11] : 255, 0, 0, 0]
        case .race: params = [b(start, max: 192), b(level, min: 1), 0, 0, outputFromStart ? 1 : 0]
        case .recoil: params = [b(start, max: 192), b(level, min: 1), b(strength, min: 1), b(frequency, min: 1), outputFromStart ? 1 : 0]
        case .sniper: params = [b(start, max: 192), b(level, min: 1), b(strength, min: 1), 0, outputFromStart ? 1 : 0]
        case .lock: params = [b(start, min: 20, max: 200), 255, 1, 0, 0]
        case .vibration:
            params = [b(start, min: 1, max: 200), b(frequency, min: 1), 1, 90, 0]
            p[2] = b(block, min: 1); p[3] = b(strength, max: 200)
            let bind: [UInt8] = [b(start, min: 1, max: 200), 1, 1, b(frequency, min: 1), 0]
            for (i, v) in bind.enumerated() { p[4 + i] = v }
        }
        for (i, v) in params.enumerated() { p[10 + i] = v }
        return p
    }

    /// Reads a trigger's adapter block back (inverse of `adapterBlock`).
    init(adapterBlock p: [UInt8]) {
        self.init()
        guard p.count >= 20, let m = Mode(rawValue: Int(p[0])) else { return }
        mode = m
        let q = Array(p[10..<15]).map { Int($0) }
        switch m {
        case .normal: break
        case .race: start = q[0]; level = q[1]; outputFromStart = q[4] != 0 || p[14] == 0xFF   // SS4 writes 0 here but always sends match on
        case .recoil: start = q[0]; level = q[1]; strength = q[2]; frequency = q[3]; outputFromStart = q[4] == 1
        case .sniper: start = q[0]; level = q[1]; strength = q[2]; outputFromStart = q[4] == 1
        case .lock: start = q[0]
        case .vibration: start = q[0]; frequency = q[1]; block = Int(p[2]); strength = Int(p[3])
        }
    }
}

/// Mode picker + the sliders that mode has in Space Station, with SS4's ranges and descriptions.
struct ForceAdaptEditor: View {
    @Binding var cfg: ForceAdapt
    var width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Picking a mode starts it from its defaults (values of another mode mean nothing to it).
            Field("Trigger mode") { DarkSelect(selection: Binding(get: { cfg.mode }, set: { m in if m != cfg.mode { cfg = .defaults(for: m) } }), options: ForceAdapt.labels, width: width) }
            switch cfg.mode {
            case .normal:
                Text("Plain linear trigger: no motor effect.").font(.system(size: 12)).foregroundStyle(SS.n400)
            case .race:
                slider("Damping start position", "Trigger travel required to activate damping feedback.", $cfg.start, 0...192)
                slider("Damping strength", "Damping feedback strength.", $cfg.level, 1...255)
                toggle("Full press at the damping start", "On (Space Station's setting): the trigger reports 100 % when it reaches the damping start, so the travel before it is your whole throttle — keep the start high for a gradual pedal. Off: the full travel maps 0–100 % and the damping is only feel.", $cfg.outputFromStart)
            case .recoil:
                slider("Start position", "Trigger travel required to activate vibration feedback.", $cfg.start, 0...192)
                slider("Start intensity", "Force required to trigger vibration once the trigger reaches the start position.", $cfg.level, 1...255)
                slider("Vibration intensity", nil, $cfg.strength, 1...255)
                slider("Vibration frequency", nil, $cfg.frequency, 1...255)
                toggle("Output data starting from the vibration start position", "The trigger reports a full press once it reaches the start position.", $cfg.outputFromStart)
            case .sniper:
                slider("Breakthrough start position", "Trigger travel required to activate breakthrough feedback.", $cfg.start, 0...192)
                slider("Breakthrough travel", "Trigger travel range for sustained breakthrough feedback.", $cfg.level, 1...255)
                slider("Breakthrough resistance", "Force required to push through once the trigger reaches the breakthrough start position.", $cfg.strength, 1...255)
                toggle("Output data starting from the breakthrough start position", "The trigger reports a full press once it reaches the breakthrough — the shot fires at the wall.", $cfg.outputFromStart)
            case .lock:
                slider("Lock position", "The trigger gets hard to push past this point, like a shorter trigger.", $cfg.start, 20...200)
            case .vibration:
                Text("The trigger vibrates together with the grip motors (game rumble).").font(.system(size: 12)).foregroundStyle(SS.n400)
                slider("Intensity coefficient", "Vibration intensity of the trigger.", $cfg.strength, 0...200)
                slider("Vibration threshold", "When the grip vibration value is below this threshold, the trigger does not vibrate.", $cfg.block, 1...255)
                slider("Travel range", "Trigger travel range for sustained vibration feedback.", $cfg.start, 1...200)
                slider("Frequency", nil, $cfg.frequency, 1...255)
            }
            if !cfg.isNormal {
                GhostButton(title: "Restore defaults", icon: "arrow.counterclockwise", enabled: !cfg.isDefault) { cfg = .defaults(for: cfg.mode) }
            }
        }
        .frame(width: width)
    }

    private func toggle(_ title: String, _ help: String, _ value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SwitchRow(title: title, isOn: value)
            Text(LocalizedStringKey(help)).font(.system(size: 11)).foregroundStyle(SS.n400)
        }
    }

    private func slider(_ title: String, _ help: String?, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Field(title) {
            VStack(alignment: .leading, spacing: 4) {
                StepSlider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                           range: Double(range.lowerBound)...Double(range.upperBound))
                if let help { Text(LocalizedStringKey(help)).font(.system(size: 11)).foregroundStyle(SS.n400) }
            }
        }
    }
}
