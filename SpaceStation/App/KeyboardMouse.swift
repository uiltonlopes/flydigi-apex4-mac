// Keyboard / mouse mapping — the macOS take on Space Station's "Special" key mapping, stick → keyboard/mouse and
// gyro → mouse. Space Station does this with a Windows kernel driver fed by its service; here the app reads the
// controller (the DInput vendor report, or GameController in XInput) and posts CGEvents, which needs the
// Accessibility permission and the app running.
//
// What the pad stores: only the flag "this key is keyboard/mouse" (0xFE in the key table) and the gyro map type
// (3 = mouse) with its activation key. Which key/click a button produces, and the stick mappings, live on this
// Mac per controller and profile slot — exactly what Space Station keeps in its local config files.
//
// Verified 2026-09-04 (apex4 dev km-probe): a key flagged 0xFE still shows in the DInput status report, but the
// firmware hides it from the XInput/Xbox report, so in XInput the app cannot see keyboard-mapped buttons.

import AppKit
import ApplicationServices
import SwiftUI
import FlydigiKit

// MARK: - Model

/// A key on the Mac keyboard: virtual key code plus the label shown in the UI.
struct KMKey: Codable, Hashable {
    var code: UInt16
    var label: String
    static let w = KMKey(code: 13, label: "W"), a = KMKey(code: 0, label: "A"), s = KMKey(code: 1, label: "S"), d = KMKey(code: 2, label: "D")
}

/// What a controller button produces (Space Station's "Special" options).
enum KMTarget: Codable, Hashable {
    case key(KMKey)
    case mouseLeft, mouseRight, wheelUp, wheelDown

    enum Kind: Hashable, CaseIterable { case key, mouseLeft, mouseRight, wheelUp, wheelDown }
    var kind: Kind {
        switch self { case .key: .key; case .mouseLeft: .mouseLeft; case .mouseRight: .mouseRight; case .wheelUp: .wheelUp; case .wheelDown: .wheelDown }
    }
    var label: String {
        switch self {
        case .key(let k): k.label
        case .mouseLeft: String(localized: "Left click")
        case .mouseRight: String(localized: "Right click")
        case .wheelUp: String(localized: "Mouse wheel up")
        case .wheelDown: String(localized: "Mouse wheel down")
        }
    }
}

struct KeyboardStick: Codable, Hashable {
    var fourWay = true
    var deadZone = 10                       // percent of travel
    var up = KMKey.w, left = KMKey.a, down = KMKey.s, right = KMKey.d
}

struct MouseStick: Codable, Hashable {
    var deadZone = 10                       // percent of travel
    var sensitivityX = 50, sensitivityY = 50  // 1…100
}

enum StickMap: Codable, Hashable {
    case joystick
    case keyboard(KeyboardStick)
    case mouse(MouseStick)
    enum Kind: Hashable { case joystick, keyboard, mouse }
    var kind: Kind { switch self { case .joystick: .joystick; case .keyboard: .keyboard; case .mouse: .mouse } }
}

struct GyroMouse: Codable, Hashable {
    var sensitivityX = 50, sensitivityY = 50  // 1…100
}

/// Everything the Mac keeps for one controller + profile slot.
struct KeyboardMouseMap: Codable, Hashable {
    var keys: [UInt8: KMTarget] = [:]        // ControllerKey raw value → target
    var leftStick: StickMap = .joystick
    var rightStick: StickMap = .joystick
    var gyro = GyroMouse()
    var isEmpty: Bool { keys.isEmpty && leftStick == .joystick && rightStick == .joystick }
    subscript(stick side: Side) -> StickMap {
        get { side == .left ? leftStick : rightStick }
        set { if side == .left { leftStick = newValue } else { rightStick = newValue } }
    }
}

// MARK: - Store (per controller mac + slot, Application Support/keyboard-mouse.json)

@MainActor @Observable
final class KeyboardMouseStore {
    private var maps: [String: KeyboardMouseMap] = [:]
    /// Bumped on every change so views and the engine can react.
    private(set) var revision = 0
    var lastError: String?

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Space Station", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keyboard-mouse.json")
    }
    init() { if let d = try? Data(contentsOf: Self.file), let m = try? JSONDecoder().decode([String: KeyboardMouseMap].self, from: d) { maps = m } }
    private func persist() { do { try JSONEncoder().encode(maps).write(to: Self.file) } catch { lastError = "\(error)" } }

    private static func id(_ mac: String?, _ slot: UInt8) -> String { "\(mac ?? "-")|\(slot)" }
    func map(for mac: String?, slot: UInt8) -> KeyboardMouseMap { maps[Self.id(mac, slot)] ?? KeyboardMouseMap() }
    func update(mac: String?, slot: UInt8, _ change: (inout KeyboardMouseMap) -> Void) {
        var m = map(for: mac, slot: slot); change(&m)
        if m.isEmpty && m.gyro == GyroMouse() { maps.removeValue(forKey: Self.id(mac, slot)) } else { maps[Self.id(mac, slot)] = m }
        revision += 1; persist()
    }

    /// Hands the engine the mapping of the slot the pad is on, plus the gyro activation rule from that slot's config.
    func push(mac: String?, slot: UInt8, motion: GamepadConfig.Motion?, connected: Bool) {
        let m = map(for: mac, slot: slot)
        let gyro = motion.map { $0.mapType == .mouse }
            .map { on in KeyboardMouseEngine.MotionRule(enabled: on, key1: motion!.enableKey1, key2: motion!.enableKey2, hold: motion!.enableType == .press) }
        KeyboardMouseEngine.shared.configure(map: connected ? m : nil, motion: gyro ?? .init(enabled: false, key1: 255, key2: 255, hold: true))
    }
}

// MARK: - Engine

/// Turns controller state into CGEvents. Fed from the raw DInput loop (any thread) or from GameController (main).
final class KeyboardMouseEngine: @unchecked Sendable {
    static let shared = KeyboardMouseEngine()

    struct MotionRule: Sendable, Equatable { var enabled: Bool; var key1: UInt8; var key2: UInt8; var hold: Bool }
    private enum Dir: Equatable { case center, right, rightTop, top, topLeft, left, leftBottom, bottom, bottomRight }

    private let lock = NSLock()
    private var map: KeyboardMouseMap?
    private var motion = MotionRule(enabled: false, key1: 255, key2: 255, hold: true)

    private var held: [UInt8: KMTarget] = [:]          // pad key → target currently down
    private var wheelNext: [UInt8: Date] = [:]
    private var lastDir: [Side: Dir] = [.left: .center, .right: .center]
    private var dirKeys: [Side: [UInt16]] = [.left: [], .right: []]
    private var accX = 0.0, accY = 0.0
    private var lastTime: Date?
    private var motionOn = false, motionKeyWasDown = false
    private var lastGyro: (Int, Int)?
    private var leftDown = false, rightDown = false
    private var screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// Whether the mapping currently pushed has anything to do.
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return map.map { !$0.isEmpty || motion.enabled } ?? false }

    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func requestTrust() { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary) }

    func configure(map: KeyboardMouseMap?, motion: MotionRule) {
        lock.lock()
        let changed = self.map != map || self.motion != motion
        if changed { releaseAllLocked() }
        self.map = map; self.motion = motion
        screen = Self.desktopBounds()
        lock.unlock()
    }

    /// One controller report. Cheap when nothing is mapped.
    func process(_ s: ControllerState) {
        lock.lock(); defer { lock.unlock() }
        guard let map, !map.isEmpty || motion.enabled else { return }
        let now = Date()
        let dt = min(0.05, lastTime.map { now.timeIntervalSince($0) } ?? 0)
        lastTime = now

        // Buttons → key / click / wheel
        for (raw, target) in map.keys {
            guard let key = ControllerKey(rawValue: raw) else { continue }
            let down = s.pressed.contains(key)
            let was = held[raw] != nil
            switch target {
            case .wheelUp, .wheelDown:
                if down, (wheelNext[raw] ?? .distantPast) <= now {
                    scroll(target == .wheelUp ? 3 : -3)
                    wheelNext[raw] = now.addingTimeInterval(was ? 0.06 : 0.25)   // first tick, then repeat while held
                }
                if down != was { if down { held[raw] = target } else { held.removeValue(forKey: raw); wheelNext.removeValue(forKey: raw) } }
            default:
                if down && !was { press(target, down: true); held[raw] = target }
                else if !down && was { press(target, down: false); held.removeValue(forKey: raw) }
            }
        }

        // Sticks
        for side in [Side.left, .right] {
            let x = side == .left ? s.leftX : s.rightX, y = side == .left ? s.leftY : s.rightY
            switch map[stick: side] {
            case .joystick: break
            case .keyboard(let k):
                let d = Self.direction(x: x, y: y, deadZone: k.deadZone, fourWay: k.fourWay)
                if d != lastDir[side] {
                    let keys = Self.keys(for: d, k)
                    for c in dirKeys[side]! where !keys.contains(c) { key(c, down: false) }
                    for c in keys where !dirKeys[side]!.contains(c) { key(c, down: true) }
                    dirKeys[side] = keys; lastDir[side] = d
                }
            case .mouse(let m):
                let dz = Float(m.deadZone) / 100
                let r = hypot(x, y)
                guard r > dz, dt > 0 else { continue }
                let scale = (r - dz) / (1 - dz) / r           // deflection beyond the dead zone, 0…1, along the same angle
                let speed = 1400.0                              // px/s at full deflection and sensitivity 50
                accX += Double(x * scale) * speed * Double(m.sensitivityX) / 50 * dt
                accY -= Double(y * scale) * speed * Double(m.sensitivityY) / 50 * dt   // screen Y grows downwards
            }
        }

        // Gyro → mouse (DInput only: the rates come from the vendor report)
        if motion.enabled {
            // 255 = no key; the second key is also "none" when it is 0 (the factory blob leaves it at 0, and Space
            // Station only reads it when the first key is set).
            let k1 = motion.key1 == 255 ? nil : ControllerKey(rawValue: motion.key1)
            let k2 = (motion.key1 == 255 || motion.key2 == 255 || motion.key2 == 0) ? nil : ControllerKey(rawValue: motion.key2)
            let keyDown = (k1.map { s.pressed.contains($0) } ?? false) || (k2.map { s.pressed.contains($0) } ?? false)
            if k1 == nil { motionOn = true }
            else if motion.hold { motionOn = keyDown }
            else { if motionKeyWasDown && !keyDown { motionOn.toggle() }; motionKeyWasDown = keyDown }
            if motionOn, let last = lastGyro {
                // Measured 2026-09-04 (apex4 dev gyro-one, ~500 reports/s): X = yaw, negative turning left, about ±120
                // for a slow turn; Y = pitch, negative when the front rises, roughly 8× more sensitive (saturates at
                // ±2047). Glitch filter like Space Station's: skip jumps of 200+ between consecutive reports (torn
                // reads show up as −256 on X). Gains give ~800 px/s for that slow turn at sensitivity 50.
                // Signs checked with the pointer on 2026-09-04: both axes come out inverted for pointing, so negate.
                // A small dead band (sensor noise at rest is ±16 on Y, a few counts on X) keeps the pointer still in hand.
                if abs(s.gyroX - last.0) < 200 && abs(s.gyroY - last.1) < 1000 {
                    let gx = abs(s.gyroX) < 4 ? 0 : s.gyroX, gy = abs(s.gyroY) < 24 ? 0 : s.gyroY
                    accX -= Double(gx) * Double(map.gyro.sensitivityX) * 0.0004
                    accY -= Double(gy) * Double(map.gyro.sensitivityY) * 0.00005
                }
            }
            lastGyro = (s.gyroX, s.gyroY)
            lastMotion = (s.gyroX, s.gyroY, motionOn, now)
        }

        flushMouse()
    }

    private var lastMotion: (x: Int, y: Int, on: Bool, at: Date)?
    /// For the Gyro tab: what the engine last saw from the sensor.
    var motionStatus: String {
        lock.lock(); defer { lock.unlock() }
        guard motion.enabled else { return String(localized: "Gyro not enabled in the applied profile.") }
        guard let m = lastMotion, Date().timeIntervalSince(m.at) < 1 else { return String(localized: "No sensor data — apply the profile and stay in DInput mode.") }
        return String(format: String(localized: "Sensor X %d · Y %d · %@"), m.x, m.y, m.on ? String(localized: "moving the pointer") : String(localized: "waiting for the activation key"))
    }

    func releaseAll() { lock.lock(); releaseAllLocked(); lock.unlock() }
    private func releaseAllLocked() {
        for (_, t) in held { if case .wheelUp = t { continue }; if case .wheelDown = t { continue }; press(t, down: false) }
        held.removeAll(); wheelNext.removeAll()
        for (_, ks) in dirKeys { for c in ks { key(c, down: false) } }
        dirKeys = [.left: [], .right: []]; lastDir = [.left: .center, .right: .center]
        accX = 0; accY = 0; lastTime = nil; motionOn = false; motionKeyWasDown = false; lastGyro = nil; lastMotion = nil
        leftDown = false; rightDown = false
    }

    // MARK: Direction (Space Station's CheckJoystickMoveDirection, with up = +Y)
    private static func direction(x: Float, y: Float, deadZone: Int, fourWay: Bool) -> Dir {
        let th = Float(deadZone) / 100
        if abs(x) <= th && abs(y) <= th { return .center }
        let a = atan2(y, x) * 180 / .pi
        if fourWay {
            if a > -45 && a <= 45 { return .right }
            if a > 45 && a <= 135 { return .top }
            if a > 135 || a <= -135 { return .left }
            return .bottom
        }
        if a > -22.5 && a <= 22.5 { return .right }
        if a > 22.5 && a <= 67.5 { return .rightTop }
        if a > 67.5 && a <= 112.5 { return .top }
        if a > 112.5 && a <= 157.5 { return .topLeft }
        if a > 157.5 || a <= -157.5 { return .left }
        if a > -157.5 && a <= -112.5 { return .leftBottom }
        if a > -112.5 && a <= -67.5 { return .bottom }
        return .bottomRight
    }
    private static func keys(for d: Dir, _ k: KeyboardStick) -> [UInt16] {
        switch d {
        case .center: []
        case .right: [k.right.code]; case .rightTop: [k.right.code, k.up.code]; case .top: [k.up.code]; case .topLeft: [k.up.code, k.left.code]
        case .left: [k.left.code]; case .leftBottom: [k.left.code, k.down.code]; case .bottom: [k.down.code]; case .bottomRight: [k.down.code, k.right.code]
        }
    }

    // MARK: Posting
    private func press(_ t: KMTarget, down: Bool) {
        switch t {
        case .key(let k): key(k.code, down: down)
        case .mouseLeft: leftDown = down; mouseButton(.left, down: down)
        case .mouseRight: rightDown = down; mouseButton(.right, down: down)
        case .wheelUp, .wheelDown: break
        }
    }
    private func key(_ code: UInt16, down: Bool) {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)?.post(tap: .cghidEventTap)
    }
    private func scroll(_ lines: Int32) {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }
    private func mouseButton(_ b: CGMouseButton, down: Bool) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = b == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: b)?.post(tap: .cghidEventTap)
    }
    private func flushMouse() {
        let ix = Int(accX.rounded(.towardZero)), iy = Int(accY.rounded(.towardZero))
        guard ix != 0 || iy != 0 else { return }
        accX -= Double(ix); accY -= Double(iy)
        let cur = CGEvent(source: nil)?.location ?? .zero
        let p = CGPoint(x: min(max(cur.x + CGFloat(ix), screen.minX), screen.maxX - 1), y: min(max(cur.y + CGFloat(iy), screen.minY), screen.maxY - 1))
        let type: CGEventType = leftDown ? .leftMouseDragged : (rightDown ? .rightMouseDragged : .mouseMoved)
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        e.post(tap: .cghidEventTap)
    }
    private static func desktopBounds() -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return (0..<Int(n)).map { CGDisplayBounds(ids[$0]) }.reduce(CGRect.null) { $0.union($1) }
    }
}

// MARK: - Key capture (press a key on the Mac keyboard)

enum KeyNames {
    static let special: [UInt16: String] = [
        49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 53: "Esc", 51: "Backspace", 117: "Delete", 71: "Clear",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 57: "Caps Lock",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        56: "Shift", 60: "Right Shift", 59: "Control", 62: "Right Control", 58: "Option", 61: "Right Option", 55: "Command", 54: "Right Command",
    ]
    static func describe(_ e: NSEvent) -> KMKey? {
        let code = e.keyCode
        if let s = special[code] { return KMKey(code: code, label: s) }
        guard e.type == .keyDown, let ch = e.charactersIgnoringModifiers, !ch.isEmpty else { return nil }
        return KMKey(code: code, label: ch.uppercased())
    }
}

struct KeyCaptureButton: View {
    var key: KMKey?
    var width: CGFloat = 120
    var onKey: (KMKey) -> Void
    @State private var armed = false
    @State private var monitor: Any?

    var body: some View {
        Button { armed.toggle() } label: {
            Text(armed ? String(localized: "Press a key…") : (key?.label ?? String(localized: "Not set")))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(armed ? SS.brand500 : .white).lineLimit(1)
                .frame(width: width, height: 30)
                .background(SS.n700, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(armed ? SS.brand500 : SS.n500, lineWidth: armed ? 2 : 1))
        }
        .buttonStyle(.plain)
        .onChange(of: armed) { _, on in
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard on else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
                if e.type == .flagsChanged, KeyNames.special[e.keyCode] == nil { return e }
                if e.type == .keyDown, e.keyCode == 53 { armed = false; return nil }          // Esc cancels
                if let k = KeyNames.describe(e) { onKey(k); armed = false; return nil }
                return e
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// The two things the engine needs, shown wherever a keyboard/mouse mapping is edited.
struct KeyboardMouseStatus: View {
    @Environment(ControllerModel.self) private var model
    @State private var trusted = KeyboardMouseEngine.isTrusted
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !trusted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SS.yellow)
                    Text("macOS needs to allow Space Station to control the keyboard and mouse (Privacy & Security › Accessibility).").font(.system(size: 12)).foregroundStyle(SS.n300)
                    GhostButton(title: "Allow…", icon: "lock.open") {
                        KeyboardMouseEngine.requestTrust()
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
                    }
                }
            }
            if model.connection == .xinput {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(SS.n300)
                    Text("Buttons mapped to the keyboard are hidden by the controller in XInput mode. Switch to DInput for keyboard and mouse mappings; sticks mapped to the mouse work in both.").font(.system(size: 12)).foregroundStyle(SS.n300)
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = KeyboardMouseEngine.isTrusted }
    }
}
