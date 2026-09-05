// flydigi-probe — read-only survey of a Flydigi controller for people who own models we cannot test.
//
// It lists the controller's USB and HID interfaces (descriptors included), records a few seconds of input
// reports while the owner presses buttons and moves the sticks, and — only on the Apex 4 family's DInput
// interface, where the command is known — asks for the device info. It never writes configuration, never
// changes modes, never flashes. The report is a text file on the Desktop meant to be sent to the maintainers
// (see docs/adding-a-controller.md).

import Foundation
import IOKit
import IOKit.hid
import IOKit.usb
import FlydigiKit

let version = "0.2.0"
let seconds: Double = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 15
let vendors: [Int] = [0x04B4, 0x37D7, 0x045E]           // classic DInput (Cypress), Flydigi's own VID, Xbox identity
nonisolated(unsafe) var report: [String] = []
func out(_ s: String) { print(s); report.append(s) }
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
func looksFlydigi(_ s: String?) -> Bool {
    guard let s = s?.lowercased() else { return false }
    return ["flydigi", "apex", "vader", "direwolf", "dunefox", "feizhi"].contains { s.contains($0) }
}

out("flydigi-probe \(version) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(ISO8601DateFormatter().string(from: Date()))")
out("Read-only: nothing is written to the controller.")
out("")

// MARK: - 1. USB registry (what macOS sees before any driver)

func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}
func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

out("== USB devices")
var usbIter: io_iterator_t = 0
var usbHits = 0
if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &usbIter) == kIOReturnSuccess {
    var dev = IOIteratorNext(usbIter)
    while dev != 0 {
        defer { IOObjectRelease(dev); dev = IOIteratorNext(usbIter) }
        let vid = int(property(dev, "idVendor")) ?? 0, pid = int(property(dev, "idProduct")) ?? 0
        let product = property(dev, "USB Product Name") as? String, vendor = property(dev, "USB Vendor Name") as? String
        guard vendors.contains(vid) || looksFlydigi(product) || looksFlydigi(vendor) else { continue }
        usbHits += 1
        out(String(format: "  %04x:%04x  \"%@\" by \"%@\"  bcdDevice %@  serial %@  speed %@", vid, pid, product ?? "?", vendor ?? "?",
                   int(property(dev, "bcdDevice")).map { String(format: "%04x", $0) } ?? "?", (property(dev, "USB Serial Number") as? String) ?? "-",
                   int(property(dev, "Device Speed")).map(String.init) ?? "?"))
        var ifIter: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(dev, kIOServicePlane, &ifIter) == kIOReturnSuccess {
            var intf = IOIteratorNext(ifIter)
            while intf != 0 {
                defer { IOObjectRelease(intf); intf = IOIteratorNext(ifIter) }
                var cls = [CChar](repeating: 0, count: 128); IOObjectGetClass(intf, &cls)
                guard String(cString: cls).contains("Interface") else { continue }
                out(String(format: "      interface %d: class %02x/%02x/%02x  alt %d  \"%@\"  endpoints %@",
                           int(property(intf, "bInterfaceNumber")) ?? -1, int(property(intf, "bInterfaceClass")) ?? 0,
                           int(property(intf, "bInterfaceSubClass")) ?? 0, int(property(intf, "bInterfaceProtocol")) ?? 0,
                           int(property(intf, "bAlternateSetting")) ?? 0, (property(intf, "USB Interface Name") as? String) ?? "-",
                           int(property(intf, "bNumEndpoints")).map(String.init) ?? "?"))
            }
            IOObjectRelease(ifIter)
        }
    }
    IOObjectRelease(usbIter)
}
if usbHits == 0 { out("  (no Flydigi-looking USB device — is the controller connected with a cable or its dongle?)") }
out("")

// MARK: - 2. HID interfaces (descriptors are the most useful part for a new model)

out("== HID interfaces")
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, nil)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
func hidProp(_ d: IOHIDDevice, _ k: String) -> Any? { IOHIDDeviceGetProperty(d, k as CFString) }
let flydigiHID = all.filter { d in
    let vid = int(hidProp(d, kIOHIDVendorIDKey)) ?? 0
    return vendors.contains(vid) || looksFlydigi(hidProp(d, kIOHIDProductKey) as? String) || looksFlydigi(hidProp(d, kIOHIDManufacturerKey) as? String)
}.sorted { (int(hidProp($0, kIOHIDLocationIDKey)) ?? 0, int(hidProp($0, kIOHIDPrimaryUsagePageKey)) ?? 0) < (int(hidProp($1, kIOHIDLocationIDKey)) ?? 0, int(hidProp($1, kIOHIDPrimaryUsagePageKey)) ?? 0) }
for (i, d) in flydigiHID.enumerated() {
    out(String(format: "  #%d  %04x:%04x  \"%@\"  usage %04x/%04x  transport %@  reports in %d / out %d / feature %d  version %@",
               i, int(hidProp(d, kIOHIDVendorIDKey)) ?? 0, int(hidProp(d, kIOHIDProductIDKey)) ?? 0, (hidProp(d, kIOHIDProductKey) as? String) ?? "?",
               int(hidProp(d, kIOHIDPrimaryUsagePageKey)) ?? 0, int(hidProp(d, kIOHIDPrimaryUsageKey)) ?? 0, (hidProp(d, kIOHIDTransportKey) as? String) ?? "?",
               int(hidProp(d, kIOHIDMaxInputReportSizeKey)) ?? 0, int(hidProp(d, kIOHIDMaxOutputReportSizeKey)) ?? 0, int(hidProp(d, kIOHIDMaxFeatureReportSizeKey)) ?? 0,
               int(hidProp(d, kIOHIDVersionNumberKey)).map { String(format: "%04x", $0) } ?? "?"))
    if let desc = hidProp(d, kIOHIDReportDescriptorKey) as? Data { out("      report descriptor (\(desc.count) B): " + hex([UInt8](desc))) }
}
if flydigiHID.isEmpty { out("  (none)") }
out("")

// MARK: - 3. Passive capture on every vendor interface

final class Capture: @unchecked Sendable {
    let lock = NSLock()
    var perId: [UInt8: (count: Int, first: [UInt8], last: [UInt8], changed: Set<Int>)] = [:]
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    func add(_ r: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        let id = r.first ?? 0
        if var e = perId[id] {
            e.count += 1
            for i in 0..<min(e.last.count, r.count) where e.last[i] != r[i] { e.changed.insert(i) }
            e.last = r; perId[id] = e
        } else { perId[id] = (1, r, r, []) }
    }
}
var captures: [(IOHIDDevice, Capture, String)] = []
let queue = DispatchQueue(label: "probe.hid")
for d in flydigiHID {
    let vid = int(hidProp(d, kIOHIDVendorIDKey)) ?? 0
    let page = int(hidProp(d, kIOHIDPrimaryUsagePageKey)) ?? 0
    let label = String(format: "%04x:%04x usage %04x", vid, int(hidProp(d, kIOHIDProductIDKey)) ?? 0, page)
    guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        out("  \(label): cannot open (owned by a system driver — normal for the Xbox identity in XInput mode)"); continue
    }
    let cap = Capture()
    IOHIDDeviceSetDispatchQueue(d, queue)
    IOHIDDeviceRegisterInputReportCallback(d, cap.buffer, 1024, { ctx, _, _, _, _, ptr, len in
        Unmanaged<Capture>.fromOpaque(ctx!).takeUnretainedValue().add(Array(UnsafeBufferPointer(start: ptr, count: Int(len))))
    }, Unmanaged.passUnretained(cap).toOpaque())
    IOHIDDeviceActivate(d)
    captures.append((d, cap, label))
}
if !captures.isEmpty {
    print("\n>>> Recording for \(Int(seconds)) s: press EVERY button once (including paddles and the extra keys), move both sticks in a full circle, pull both triggers, and shake the controller a little.")
    let t0 = Date()
    while Date().timeIntervalSince(t0) < seconds { Thread.sleep(forTimeInterval: 0.5); let left = Int(seconds - Date().timeIntervalSince(t0)); if left % 5 == 0 { print("    \(left) s…") } }
    out("== Input reports (\(Int(seconds)) s)")
    for (d, cap, label) in captures {
        IOHIDDeviceCancel(d)
        out("  \(label)")
        cap.lock.lock()
        if cap.perId.isEmpty { out("      no input reports") }
        for (id, e) in cap.perId.sorted(by: { $0.key < $1.key }) {
            out(String(format: "      report id %02x: %d reports (%d B)  changing bytes: %@", id, e.count, e.first.count, e.changed.sorted().map(String.init).joined(separator: ",")))
            out("        first: " + hex(e.first))
            out("        last:  " + hex(e.last))
        }
        cap.lock.unlock()
    }
    out("")
}

// MARK: - 4. Known-safe query (classic DInput interface only)

if let d = flydigiHID.first(where: { int(hidProp($0, kIOHIDVendorIDKey)) == 0x04B4 && int(hidProp($0, kIOHIDProductIDKey)) == 0x2412 && int(hidProp($0, kIOHIDPrimaryUsagePageKey)) == 0xFFA0 }) {
    out("== Classic DInput device info (05 EC)")
    let cap = Capture()
    IOHIDDeviceSetDispatchQueue(d, queue)
    IOHIDDeviceRegisterInputReportCallback(d, cap.buffer, 1024, { ctx, _, _, _, _, ptr, len in
        Unmanaged<Capture>.fromOpaque(ctx!).takeUnretainedValue().add(Array(UnsafeBufferPointer(start: ptr, count: Int(len))))
    }, Unmanaged.passUnretained(cap).toOpaque())
    IOHIDDeviceActivate(d)
    let cmd = DInput.command(DInput.Cmd.deviceInfo)
    let r = cmd.withUnsafeBufferPointer { IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, CFIndex(cmd[0]), $0.baseAddress!, $0.count) }
    if r == kIOReturnSuccess {
        Thread.sleep(forTimeInterval: 1.0)
        cap.lock.lock()
        let replies = cap.perId.values.map(\.last).filter { $0.count > 3 && $0[1] == 0xFF }
        cap.lock.unlock()
        if let reply = replies.first, let info = DInputReply.deviceInfo(reply) {
            out("  device id \(info.deviceId) (\(info.modelName)) · firmware \(info.firmware) · \(info.isWired ? "wired" : "wireless") · reply: \(hex(reply))")
        } else { out("  no device-info reply") }
    } else { out(String(format: "  write failed 0x%08x", r)) }
    IOHIDDeviceCancel(d)
    out("")
}
for (d, _, _) in captures { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone)) }

// MARK: - 5. Save

let stamp = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }()
let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
let file = desktop.appendingPathComponent("flydigi-probe-\(stamp).txt")
do {
    try report.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    print("\nSaved \(file.path)\nPlease send this file with the controller model, its firmware version and whether it was on the cable or the dongle.")
} catch { print("could not save the report: \(error)") }
