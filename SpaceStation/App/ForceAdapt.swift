// ForceAdapt (adaptive trigger) modes exactly as Space Station 4 offers them for the Apex 4 (k2), with the
// same labels, parameters and ranges. Reference: SS4's `SetForceTriggerCommandFactory` (live command),
// `SaveTriggerAdapterConfig` (profile blob) and the renderer's trigger tab (labels, min/max).
//
// Note the naming trap in SS4: its enum value `Sniper` (type 2) is *labelled* "Machine gun" in the UI and its
// enum value `Recoil` (type 3) is labelled "Sniper". We use the UI names; the byte values are the enum's.

import SwiftUI
import FlydigiKit
import FlydigiTransport

struct ForceAdapt: Codable, Hashable {
    enum Mode: Int, Codable, CaseIterable, Hashable {
        case normal = 0, race = 1, machineGun = 2, sniper = 3, lock = 4, vibration = 5
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
    /// Machine gun / sniper: "output data from the start position" (SS4's MatchStart).
    var outputFromStart = true

    static let labels: [(Mode, String)] = [(.normal, "Normal"), (.race, "Racing"), (.machineGun, "Machine gun"), (.sniper, "Sniper"), (.lock, "Trigger lock"), (.vibration, "Vibration")]
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
        outputFromStart = (try? c.decode(Bool.self, forKey: .outputFromStart)) ?? true
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
        case .race: return [1, b(start, max: 192), b(level, min: 1), 1]
        case .machineGun: return [2, b(start, max: 192), b(level, min: 1), b(strength, min: 1), b(frequency, min: 1), outputFromStart ? 1 : 0]
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
        case .race: params = [b(start, max: 192), b(level, min: 1), 0, 0, 0]
        case .machineGun: params = [b(start, max: 192), b(level, min: 1), b(strength, min: 1), b(frequency, min: 1), outputFromStart ? 1 : 0]
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
        case .race: start = q[0]; level = q[1]
        case .machineGun: start = q[0]; level = q[1]; strength = q[2]; frequency = q[3]; outputFromStart = q[4] == 1
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
            Field("Trigger mode") { DarkSelect(selection: $cfg.mode, options: ForceAdapt.labels, width: width) }
            switch cfg.mode {
            case .normal:
                Text("Plain trigger: no motor effect.").font(.system(size: 12)).foregroundStyle(SS.n400)
            case .race:
                slider("Damping start position", "Trigger travel where the damping starts.", $cfg.start, 0...192)
                slider("Damping force", "How hard the trigger resists past that point.", $cfg.level, 1...255)
            case .machineGun:
                slider("Vibration start position", "Trigger travel where the vibration starts.", $cfg.start, 0...192)
                slider("Vibration start force", "Force needed, past the start position, to make it vibrate.", $cfg.level, 1...255)
                slider("Vibration strength", nil, $cfg.strength, 1...255)
                slider("Vibration frequency", nil, $cfg.frequency, 1...255)
                SwitchRow(title: "Output data from the start position", isOn: $cfg.outputFromStart)
            case .sniper:
                slider("Breakthrough start position", "Trigger travel where the resistance wall begins.", $cfg.start, 0...192)
                slider("Breakthrough stroke", "How long the wall lasts.", $cfg.level, 1...255)
                slider("Breakthrough resistance", "Force needed to push through it.", $cfg.strength, 1...255)
                SwitchRow(title: "Output data from the start position", isOn: $cfg.outputFromStart)
            case .lock:
                slider("Lock position", "The trigger stops here, like a shorter trigger.", $cfg.start, 20...200)
            case .vibration:
                Text("The trigger vibrates together with the grip motors.").font(.system(size: 12)).foregroundStyle(SS.n400)
                slider("Strength coefficient", nil, $cfg.strength, 0...200)
                slider("Shield value", "Grip vibration below this value does not move the trigger.", $cfg.block, 1...255)
                slider("Stroke", "Trigger travel over which it vibrates.", $cfg.start, 1...200)
                slider("Frequency", nil, $cfg.frequency, 1...255)
            }
        }
        .frame(width: width)
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
