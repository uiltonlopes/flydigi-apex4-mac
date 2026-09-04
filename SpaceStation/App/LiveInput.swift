// Live stick/trigger/button readout through the GameController framework. Works in both USB modes
// (Apple's Xbox dext in XInput; generic HID gamepad in DInput). Content-layer visualisation only.

import Foundation
import GameController
import Observation
import FlydigiKit
import FlydigiTransport
import os.log

@MainActor @Observable
final class LiveInput {
    struct Stick: Equatable { var x: Float = 0, y: Float = 0 }
    var left = Stick()
    var right = Stick()
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
    var pressed: Set<String> = []
    var connected = false
    struct BatteryInfo: Equatable { var level: Float; var charging: Bool }
    var battery: BatteryInfo?
    /// Input reports per second seen on the raw DInput link (SS4's polling-rate meter). nil while not monitoring.
    var rawReportRate: Int?
    private var batteryTimer: Timer?

    /// Raw state from the DInput vendor interface (paddles, Fn, Home — things the system driver never sees).
    var raw: ControllerState?
    private var rawTask: Task<Void, Never>?

    /// Same information as `pressed`, as firmware key ids (triggers count as pressed past 50 %),
    /// merged with the raw DInput report when we have one.
    var pressedKeys: Set<ControllerKey> {
        var s = Set(pressed.compactMap { Self.keyForLabel[$0] })
        if leftTrigger > 0.5 { s.insert(.lt) }
        if rightTrigger > 0.5 { s.insert(.rt) }
        if let raw { s.formUnion(raw.pressed) }
        return s
    }

    /// Start/stop reading the vendor interface directly. Only possible in DInput mode; harmless to call twice.
    func setRawMonitoring(_ on: Bool) {
        if !on { rawTask?.cancel(); rawTask = nil; raw = nil; rawReportRate = nil; return }
        guard rawTask == nil else { return }
        let engine = KeyboardMouseEngine.shared
        rawTask = Task.detached(priority: .utility) { [weak self] in
            guard let link = try? HIDLink() else { return }
            defer { link.close() }
            var last: ControllerState?
            var connectedSeen = false
            var count = 0, windowStart = Date()
            while !Task.isCancelled {
                let state: ControllerState? = try? link.waitForReport(timeout: 0.25) { (r: [UInt8]) -> ControllerState? in ControllerState(dinputReport: r) }
                if state != nil { count += 1 } else { engine.releaseAll() }      // pad silent: never leave a key held down
                if Date().timeIntervalSince(windowStart) >= 1 {
                    let rate = count; count = 0; windowStart = Date()
                    await MainActor.run { [weak self] in self?.rawReportRate = rate }
                }
                guard let state else { continue }
                engine.process(state)                     // keyboard/mouse mapping, every report
                if state != last || !connectedSeen {
                    last = state; connectedSeen = true
                    await MainActor.run { [weak self] in self?.raw = state; self?.connected = true }
                }
            }
        }
    }
    private static let keyForLabel: [String: ControllerKey] = [
        "A": .a, "B": .b, "X": .x, "Y": .y, "LB": .lb, "RB": .rb, "LS": .thumbL, "RS": .thumbR,
        "▲": .up, "▼": .down, "◀": .left, "▶": .right, "≡": .start, "◧": .select, "⌂": .home,
    ]

    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.attach() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.attach() }
        })
        attach()
    }

    private func readBattery(from pad: GCController) {
        // Over the 2.4 GHz receiver macOS exposes a battery object with state "unknown" and level 0 — that is
        // no information, not an empty battery; leave it nil so the pad's own byte is used instead.
        guard let b = pad.battery, b.batteryState != .unknown, b.batteryLevel > 0 else { battery = nil; return }
        battery = BatteryInfo(level: b.batteryLevel, charging: b.batteryState == .charging || b.batteryState == .full)
    }

    private func attach() {
        // Prefer a Flydigi pad; otherwise the first extended gamepad.
        let all = GCController.controllers()
        let pad = all.first { ($0.vendorName ?? "").localizedCaseInsensitiveContains("flydigi") } ?? all.first { $0.extendedGamepad != nil }
        connected = pad != nil
        batteryTimer?.invalidate(); batteryTimer = nil; battery = nil
        if let pad, pad.battery != nil {
            readBattery(from: pad)
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in if let self, let pad = GCController.controllers().first(where: { $0.battery != nil }) { self.readBattery(from: pad) } }
            }
        }
        if let pad {
            let names = pad.physicalInputProfile.elements.keys.sorted().joined(separator: ", ")
            Logger(subsystem: "com.uiltonlopes.spacestation", category: "live").notice("GameController pad \(pad.vendorName ?? "?", privacy: .public) [\(pad.productCategory, privacy: .public)] elements: \(names, privacy: .public)")
        }
        guard let gp = pad?.extendedGamepad else { return }
        gp.valueChangedHandler = { [weak self] gamepad, _ in
            guard let self else { return }
            Task { @MainActor in
                self.left = Stick(x: gamepad.leftThumbstick.xAxis.value, y: gamepad.leftThumbstick.yAxis.value)
                self.right = Stick(x: gamepad.rightThumbstick.xAxis.value, y: gamepad.rightThumbstick.yAxis.value)
                self.leftTrigger = gamepad.leftTrigger.value
                self.rightTrigger = gamepad.rightTrigger.value
                var p: Set<String> = []
                if gamepad.buttonA.isPressed { p.insert("A") }; if gamepad.buttonB.isPressed { p.insert("B") }
                if gamepad.buttonX.isPressed { p.insert("X") }; if gamepad.buttonY.isPressed { p.insert("Y") }
                if gamepad.leftShoulder.isPressed { p.insert("LB") }; if gamepad.rightShoulder.isPressed { p.insert("RB") }
                if gamepad.leftThumbstickButton?.isPressed == true { p.insert("LS") }; if gamepad.rightThumbstickButton?.isPressed == true { p.insert("RS") }
                if gamepad.dpad.up.isPressed { p.insert("▲") }; if gamepad.dpad.down.isPressed { p.insert("▼") }
                if gamepad.dpad.left.isPressed { p.insert("◀") }; if gamepad.dpad.right.isPressed { p.insert("▶") }
                if gamepad.buttonMenu.isPressed { p.insert("≡") }; if gamepad.buttonOptions?.isPressed == true { p.insert("◧") }
                if gamepad.buttonHome?.isPressed == true { p.insert("⌂") }
                self.pressed = p
                // XInput: no vendor report, so the engine gets what the system driver shows (sticks and plain buttons).
                if self.raw == nil {
                    KeyboardMouseEngine.shared.process(ControllerState(pressed: self.pressedKeys, leftX: self.left.x, leftY: self.left.y, rightX: self.right.x, rightY: self.right.y,
                                                                       leftTrigger: self.leftTrigger, rightTrigger: self.rightTrigger))
                }
            }
        }
    }
}
