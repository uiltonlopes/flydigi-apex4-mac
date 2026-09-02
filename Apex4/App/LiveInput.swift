// Live stick/trigger/button readout through the GameController framework. Works in both USB modes
// (Apple's Xbox dext in XInput; generic HID gamepad in DInput). Content-layer visualisation only.

import Foundation
import GameController
import Observation

@MainActor @Observable
final class LiveInput {
    struct Stick: Equatable { var x: Float = 0, y: Float = 0 }
    var left = Stick()
    var right = Stick()
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
    var pressed: Set<String> = []
    var connected = false

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

    private func attach() {
        // Prefer a Flydigi pad; otherwise the first extended gamepad.
        let all = GCController.controllers()
        let pad = all.first { ($0.vendorName ?? "").localizedCaseInsensitiveContains("flydigi") } ?? all.first { $0.extendedGamepad != nil }
        connected = pad != nil
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
                self.pressed = p
            }
        }
    }
}
