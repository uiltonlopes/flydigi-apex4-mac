// XInput transport: the Xbox-360-style interface (045e:028e, interface 0, OUT ep5 / IN ep1).
//
// Apple's XboxGamepad dext owns this interface, so the device has to be *captured*. This file uses the
// classic IOUSBLib user-client API (IOKit.usb) and mirrors libusb's darwin backend step by step:
//   open (USBDeviceOpenSeize) → USBDeviceReEnumerate(kUSBReEnumerateCaptureDeviceMask) → close/re-open →
//   ensure configuration → claim interface 0 (USBInterfaceOpen) → synchronous interrupt I/O →
//   release: USBInterfaceClose → USBDeviceReEnumerate(0) (drivers re-match) → USBDeviceClose.
// That exact sequence ran dozens of times through libusb/pyusb on this machine without incident, whereas
// the IOUSBHost capture path panicked the kernel on macOS 26.6 (2026-09-01) — see docs/architecture.md.
//
// ⚠️ Still requires root and still terminates Apple's driver for the pad while open. Run deliberately.

import Foundation
import IOKit
import IOKit.usb
import FlydigiKit

private typealias DeviceInterface = IOUSBDeviceInterface650
private typealias InterfaceInterface = IOUSBInterfaceInterface800
private typealias DevicePtr = UnsafeMutablePointer<UnsafeMutablePointer<DeviceInterface>?>
private typealias InterfacePtr = UnsafeMutablePointer<UnsafeMutablePointer<InterfaceInterface>?>

/// UUIDs from IOUSBLib.h / IOCFPlugIn.h (macros Swift cannot import).
private enum UUIDs {
    static var cfPlugIn: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F) }
    static var deviceUserClient: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil, 0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4, 0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61) }
    static var interfaceUserClient: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil, 0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4, 0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61) }
    static var deviceInterface650: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil, 0x4A, 0xAC, 0x1B, 0x2E, 0x24, 0xC2, 0x47, 0x6A, 0x96, 0x4D, 0x91, 0x33, 0x35, 0x34, 0xF2, 0xCC) }
    static var interfaceInterface800: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil, 0x33, 0xA8, 0x5D, 0xB0, 0x0C, 0x3B, 0x43, 0x28, 0x8F, 0x02, 0xFD, 0xA8, 0x1B, 0x11, 0x7F, 0x4C) }
}

private let captureMask: UInt32 = 1 << 30      // kUSBReEnumerateCaptureDeviceMask

public final class USBLink: Link, @unchecked Sendable {
    public let channel: Channel = .xinput

    private var device: DevicePtr
    private var interface: InterfacePtr?
    private var inPipe: UInt8 = 0
    private var outPipe: UInt8 = 0
    /// The other OUT endpoint of interface 0 — where a game's Xbox 360 rumble packet goes (ep2 on the wired pad).
    private var rumblePipe: UInt8 = 0
    public private(set) var endpointSummary = ""
    private let lock = NSLock()
    private var inbox: [[UInt8]] = []
    private let arrived = DispatchSemaphore(value: 0)
    private var closed = false
    private var reader: Thread?

    /// Captures the first Apex 4 (or its 2.4 GHz receiver) in XInput mode. Needs root.
    public init() throws {
        guard geteuid() == 0 else {
            throw TransportError.io("XInput access needs root (Apple's Xbox driver owns the interface). Re-run with sudo, or use the privileged helper.")
        }
        let match = IOServiceMatching("IOUSBHostDevice")! as NSMutableDictionary
        match["idVendor"] = Int(USBID.xinputVendor)
        match["idProduct"] = Int(USBID.xinputProduct)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, match as CFDictionary)
        guard service != IO_OBJECT_NULL else {
            throw TransportError.notFound("Apex 4 not found in XInput mode (045e:028e). Plug it in over USB and switch to XInput.")
        }
        defer { IOObjectRelease(service) }

        device = try Self.deviceInterface(for: service)
        var kr = device.pointee!.pointee.USBDeviceOpenSeize(device)
        guard kr == kIOReturnSuccess || kr == kIOReturnExclusiveAccess else { Self.release(device); throw Self.err("USBDeviceOpenSeize", kr) }

        // Capture: terminates Apple's driver stack for this device. Does not re-enumerate, but requires a re-open.
        kr = device.pointee!.pointee.USBDeviceReEnumerate(device, captureMask)
        guard kr == kIOReturnSuccess else { _ = device.pointee!.pointee.USBDeviceClose(device); Self.release(device); throw Self.err("USBDeviceReEnumerate(capture)", kr) }
        // libusb's darwin_restore_state: close and re-open the *same* device interface (no re-creation).
        _ = device.pointee!.pointee.USBDeviceClose(device)
        kr = device.pointee!.pointee.USBDeviceOpenSeize(device)
        guard kr == kIOReturnSuccess else { Self.release(device); throw Self.err("USBDeviceOpenSeize (after capture)", kr) }

        var config: UInt8 = 0
        _ = device.pointee!.pointee.GetConfiguration(device, &config)
        if config == 0 {
            kr = device.pointee!.pointee.SetConfiguration(device, 1)
            guard kr == kIOReturnSuccess else { teardownDevice(reattach: true); throw Self.err("SetConfiguration(1)", kr) }
        }

        do {
            let ifService = try Self.interfaceService(of: device, number: 0)
            defer { IOObjectRelease(ifService) }
            interface = try Self.interfaceInterface(for: ifService)
        } catch {
            teardownDevice(reattach: true)
            throw error
        }
        let intf = interface!
        kr = intf.pointee!.pointee.USBInterfaceOpen(intf)
        guard kr == kIOReturnSuccess else { Self.release(intf); interface = nil; teardownDevice(reattach: true); throw Self.err("USBInterfaceOpen", kr) }

        // Map endpoint addresses to pipe references.
        var numEndpoints: UInt8 = 0
        _ = intf.pointee!.pointee.GetNumEndpoints(intf, &numEndpoints)
        for pipeRef in 1...max(1, numEndpoints) {
            var direction: UInt8 = 0, number: UInt8 = 0, transferType: UInt8 = 0, interval: UInt8 = 0
            var maxPacket: UInt16 = 0
            guard intf.pointee!.pointee.GetPipeProperties(intf, pipeRef, &direction, &number, &transferType, &maxPacket, &interval) == kIOReturnSuccess else { continue }
            endpointSummary += "\(direction == UInt8(kUSBIn) ? "IN" : "OUT")\(number)(max \(maxPacket)) "
            if direction == UInt8(kUSBIn) && number == 1 { inPipe = pipeRef }
            if direction == UInt8(kUSBOut) && number == 5 { outPipe = pipeRef }
            if direction == UInt8(kUSBOut) && number != 5 && rumblePipe == 0 { rumblePipe = pipeRef }
        }
        guard inPipe != 0, outPipe != 0 else { close(); throw TransportError.io("interface 0 does not expose IN ep1 / OUT ep5 (found \(numEndpoints) endpoints)") }

        startReader()
    }

    // MARK: Link

    public func write(_ packet: [UInt8]) throws {
        guard let intf = interface, !closed else { throw TransportError.io("link closed") }
        var buf = packet
        let kr = buf.withUnsafeMutableBytes { intf.pointee!.pointee.WritePipe(intf, outPipe, $0.baseAddress, UInt32(packet.count)) }
        guard kr == kIOReturnSuccess else { throw Self.err("WritePipe", kr) }
    }

    /// Writes an Xbox 360 output packet (rumble / LED) on the pad's XInput OUT endpoint, not the Flydigi one.
    public func writeXbox(_ packet: [UInt8]) throws {
        guard let intf = interface, !closed else { throw TransportError.io("link closed") }
        guard rumblePipe != 0 else { throw TransportError.io("no second OUT endpoint (endpoints: \(endpointSummary))") }
        var buf = packet
        let kr = buf.withUnsafeMutableBytes { intf.pointee!.pointee.WritePipe(intf, rumblePipe, $0.baseAddress, UInt32(packet.count)) }
        guard kr == kIOReturnSuccess else { throw Self.err("WritePipe(xbox)", kr) }
    }

    public func waitForReport<T>(timeout: TimeInterval, _ match: @Sendable @escaping ([UInt8]) -> T?) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            while !inbox.isEmpty {
                let r = inbox.removeFirst()
                if let v = match(r) { lock.unlock(); return v }
            }
            lock.unlock()
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw TransportError.timeout("no matching report within \(timeout)s") }
            _ = arrived.wait(timeout: .now() + remaining)
        }
    }

    /// Releases the interface and asks macOS to re-enumerate the device so Apple's driver comes back.
    public func discardPending() { lock.lock(); inbox.removeAll(); lock.unlock() }

    public func close() { close(reattach: true) }

    /// Releases without `USBDeviceReEnumerate(0)`: the controller is about to re-enumerate itself.
    public func closeWithoutReset() { close(reattach: false) }

    private func close(reattach: Bool) {
        guard !closed else { return }
        closed = true
        if let intf = interface {
            _ = intf.pointee!.pointee.AbortPipe(intf, inPipe)          // unblocks the reader thread
            _ = intf.pointee!.pointee.USBInterfaceClose(intf)
            Self.release(intf)
            interface = nil
        }
        teardownDevice(reattach: reattach)
    }

    // MARK: Internals

    private func startReader() {
        let t = Thread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 64)
            while let self, !self.closed, let intf = self.interface {
                var size: UInt32 = 64
                let kr = buf.withUnsafeMutableBytes { intf.pointee!.pointee.ReadPipe(intf, self.inPipe, $0.baseAddress, &size) }
                if kr == kIOReturnSuccess, size > 0 {
                    let report = Array(buf[0..<Int(size)])
                    self.lock.lock(); self.inbox.append(report); if self.inbox.count > 512 { self.inbox.removeFirst() }; self.lock.unlock()
                    self.arrived.signal()
                } else if kr == kIOReturnAborted || kr == kIOReturnNotOpen || kr == kIOReturnNoDevice {
                    return
                } else {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
        t.name = "flydigi.usb.reader"
        t.start()
        reader = t
    }

    /// Close the device; with `reattach`, re-enumerate without the capture mask so drivers re-match (libusb's attach_kernel_driver).
    private func teardownDevice(reattach: Bool) {
        if reattach { _ = device.pointee!.pointee.USBDeviceReEnumerate(device, 0) }
        _ = device.pointee!.pointee.USBDeviceClose(device)
        Self.release(device)
    }

    private static func deviceInterface(for service: io_service_t) throws -> DevicePtr {
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        var kr = kIOReturnSuccess
        for _ in 0..<5 {   // libusb retries: the first attempt can fail with "out of resources"
            kr = IOCreatePlugInInterfaceForService(service, UUIDs.deviceUserClient, UUIDs.cfPlugIn, &plugIn, &score)
            if kr == kIOReturnSuccess, plugIn != nil { break }
            usleep(1000)
        }
        guard kr == kIOReturnSuccess, let plugIn else { throw err("IOCreatePlugInInterfaceForService(device)", kr) }
        defer { _ = plugIn.pointee!.pointee.Release(plugIn) }
        var raw: LPVOID?
        let hr = plugIn.pointee!.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(UUIDs.deviceInterface650), &raw)
        guard hr == S_OK, let raw else { throw TransportError.io("QueryInterface(IOUSBDeviceInterface650) failed: \(hr)") }
        return DevicePtr(OpaquePointer(raw))
    }

    private static func interfaceService(of device: DevicePtr, number: UInt8) throws -> io_service_t {
        var request = IOUSBFindInterfaceRequest(bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
                                                bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
                                                bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
                                                bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare))
        var iterator: io_iterator_t = 0
        let kr = device.pointee!.pointee.CreateInterfaceIterator(device, &request, &iterator)
        guard kr == kIOReturnSuccess else { throw err("CreateInterfaceIterator", kr) }
        defer { IOObjectRelease(iterator) }
        while case let s = IOIteratorNext(iterator), s != IO_OBJECT_NULL {
            if let n = IORegistryEntryCreateCFProperty(s, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int, n == Int(number) {
                return s
            }
            IOObjectRelease(s)
        }
        throw TransportError.io("interface \(number) not found after capture")
    }

    private static func interfaceInterface(for service: io_service_t) throws -> InterfacePtr {
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let kr = IOCreatePlugInInterfaceForService(service, UUIDs.interfaceUserClient, UUIDs.cfPlugIn, &plugIn, &score)
        guard kr == kIOReturnSuccess, let plugIn else { throw err("IOCreatePlugInInterfaceForService(interface)", kr) }
        defer { _ = plugIn.pointee!.pointee.Release(plugIn) }
        var raw: LPVOID?
        let hr = plugIn.pointee!.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(UUIDs.interfaceInterface800), &raw)
        guard hr == S_OK, let raw else { throw TransportError.io("QueryInterface(IOUSBInterfaceInterface800) failed: \(hr)") }
        return InterfacePtr(OpaquePointer(raw))
    }

    private static func release(_ p: DevicePtr) { _ = p.pointee!.pointee.Release(UnsafeMutableRawPointer(p)) }
    private static func release(_ p: InterfacePtr) { _ = p.pointee!.pointee.Release(UnsafeMutableRawPointer(p)) }

    private static func err(_ what: String, _ kr: IOReturn) -> TransportError {
        .io(String(format: "%@ failed: 0x%08x", what, UInt32(bitPattern: kr)))
    }
}
