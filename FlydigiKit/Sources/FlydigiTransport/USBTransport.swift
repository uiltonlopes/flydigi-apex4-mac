// XInput transport: the Xbox-360-style interface (045e:028e, interface 0, OUT ep5 / IN ep1) via IOUSBHost.
// Apple's XboxGamepad dext owns this interface, so we *capture* the device — which requires root
// (or the com.apple.vm.device-access entitlement). See docs/architecture.md.

import Foundation
import IOKit
import IOUSBHost
import FlydigiKit

public final class USBLink: Link, @unchecked Sendable {
    public let channel: Channel = .xinput
    private let device: IOUSBHostDevice
    private let interface: IOUSBHostInterface
    private let outPipe: IOUSBHostPipe
    private let inPipe: IOUSBHostPipe
    private let queue = DispatchQueue(label: "flydigi.usb")
    private let lock = NSLock()
    private var inbox: [[UInt8]] = []
    private let arrived = DispatchSemaphore(value: 0)
    private var closed = false

    static let outEndpoint = 0x05
    static let inEndpoint = 0x81

    public init() throws {
        guard getuid() == 0 else {
            throw TransportError.io("XInput access needs root (Apple's Xbox driver owns the interface). Re-run with sudo, or use the privileged helper.")
        }
        // 1. Find the device service and capture it (terminates Apple's dext clients for this device).
        let devMatch = IOUSBHostDevice.__createMatchingDictionary(
            withVendorID: NSNumber(value: USBID.xinputVendor), productID: NSNumber(value: USBID.xinputProduct),
            bcdDevice: nil, deviceClass: nil, deviceSubclass: nil, deviceProtocol: nil, speed: nil, productIDArray: nil
        ).takeRetainedValue()
        let devService = IOServiceGetMatchingService(kIOMainPortDefault, devMatch)
        guard devService != IO_OBJECT_NULL else {
            throw TransportError.notFound("Apex 4 not found in XInput mode (045e:028e). Plug it in over USB and switch to XInput.")
        }
        do {
            device = try IOUSBHostDevice(__ioService: devService, options: .deviceCapture, queue: queue, interestHandler: nil)
        } catch {
            throw TransportError.io("device capture failed: \(error.localizedDescription)")
        }
        // 2. Open interface 0 and its two interrupt pipes. With matchInterfaces:false the interface nubs
        // exist but are not registered for matching, so IOServiceGetMatchingService cannot see them:
        // walk the device's children in the IORegistry instead.
        var ifService: io_service_t = IO_OBJECT_NULL
        let deadline = Date().addingTimeInterval(5)
        while ifService == IO_OBJECT_NULL && Date() < deadline {
            ifService = Self.childInterface(of: devService, number: 0)
            if ifService == IO_OBJECT_NULL { Thread.sleep(forTimeInterval: 0.1) }
        }
        guard ifService != IO_OBJECT_NULL else { device.destroy(); throw TransportError.io("interface 0 not published after capture (waited 5s)") }
        do {
            interface = try IOUSBHostInterface(__ioService: ifService, options: [], queue: queue, interestHandler: nil)
        } catch {
            device.destroy()
            throw TransportError.io("interface open failed: \(error.localizedDescription) (see docs/architecture.md, risk #1)")
        }
        do {
            outPipe = try interface.copyPipe(withAddress: Self.outEndpoint)
            inPipe = try interface.copyPipe(withAddress: Self.inEndpoint)
        } catch {
            interface.destroy(); device.destroy()
            throw TransportError.io("pipes: \(error.localizedDescription)")
        }
        armRead()
    }

    /// Finds the IOUSBHostInterface child of `device` with the given bInterfaceNumber (registered or not).
    private static func childInterface(of device: io_service_t, number: Int) -> io_service_t {
        var iter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &iter) == kIOReturnSuccess else { return IO_OBJECT_NULL }
        defer { IOObjectRelease(iter) }
        while case let child = IOIteratorNext(iter), child != IO_OBJECT_NULL {
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
               let n = IORegistryEntryCreateCFProperty(child, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
               n == number {
                return child
            }
            IOObjectRelease(child)
        }
        return IO_OBJECT_NULL
    }

    /// Keeps one asynchronous read outstanding on the IN pipe; every completed report lands in `inbox`.
    private final class ReadBuffer: @unchecked Sendable { let data = NSMutableData(length: 64)! }

    private func armRead() {
        let box = ReadBuffer()
        do {
            try inPipe.enqueueIORequest(with: box.data, completionTimeout: 0) { [weak self] status, transferred in
                guard let self, !self.closed else { return }
                if status == kIOReturnSuccess, transferred > 0 {
                    let bytes = [UInt8](box.data.prefix(Int(transferred)))
                    self.lock.lock(); self.inbox.append(bytes); self.lock.unlock(); self.arrived.signal()
                }
                if status == kIOReturnSuccess || status == kIOReturnTimeout { self.armRead() }
            }
        } catch {
            // Device went away; waiters will time out.
        }
    }

    public func write(_ packet: [UInt8]) throws {
        let data = NSMutableData(bytes: packet, length: packet.count)
        var sent: Int = 0
        do {
            try outPipe.__sendIORequest(with: data, bytesTransferred: &sent, completionTimeout: 0)
        } catch {
            throw TransportError.io("USB write failed: \(error.localizedDescription)")
        }
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

    /// Releases the device; macOS re-matches Apple's driver so the pad works as a gamepad again.
    public func close() {
        guard !closed else { return }
        closed = true
        try? inPipe.__abort(with: .synchronous)
        interface.destroy()
        device.destroy()
    }
}
