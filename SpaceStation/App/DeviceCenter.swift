// Space Station's welcome / device-center screen: full-bleed dark stage with the connected controller as
// a card (name, connection, battery, product picture). Clicking the card opens the controller pages.

import SwiftUI
import FlydigiKit

struct DeviceCenterPage: View {
    @Environment(ControllerModel.self) private var model
    @Environment(LiveInput.self) private var live
    @Binding var route: Route
    @State private var showHelp = false

    private var connected: Bool { model.connection != .none }

    var body: some View {
        GeometryReader { g in
            ZStack {
                SS.n900
                // SS4's diagonal blue wash in the top-right corner.
                Ellipse().fill(SS.brand.opacity(0.35)).frame(width: g.size.width * 0.6, height: g.size.height * 1.2)
                    .rotationEffect(.degrees(35)).blur(radius: 120).offset(x: g.size.width * 0.35, y: -g.size.height * 0.35)

                VStack(spacing: 0) {
                    Text("Welcome to Space Station").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
                        .padding(.top, max(80, g.size.height * 0.16))
                    Spacer()
                    if connected { deviceCard } else { emptyCard }
                    Spacer()
                }

                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Button { route = .settings } label: {
                            Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(SS.n300)
                                .frame(width: 44, height: 44)
                                .background(SS.n700.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
                        }
                        .buttonStyle(.plain)
                        Button { showHelp.toggle() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.dashed").font(.system(size: 15))
                                Text("Add Device").font(.system(size: 15))
                            }
                            .foregroundStyle(SS.brand500).padding(.horizontal, 18).frame(height: 44)
                            .background(SS.n700.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.brand500.opacity(0.7)))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showHelp, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Connecting a controller").font(.headline)
                                Text("Plug the controller in over USB-C, or plug its charging base in and power the controller on (2.4 GHz). It appears here automatically; Bluetooth cannot be configured.")
                                    .font(.callout).foregroundStyle(.secondary).frame(width: 320)
                                Text(model.helperInstalled ? "" : "In XInput mode the helper is required — install it in Settings.").font(.callout).foregroundStyle(SS.yellow)
                            }
                            .padding(16)
                        }
                        Spacer()
                    }
                    .padding(24)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var deviceName: String {
        model.info.flatMap { DeviceCatalog.descriptor(for: $0.deviceId)?.name } ?? "Flydigi controller"
    }

    private var deviceCard: some View {
        Button { route = .home } label: {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if let i = model.info {
                        Image(systemName: i.wired ? "cable.connector" : "dot.radiowaves.left.and.right").font(.system(size: 12)).foregroundStyle(SS.n300)
                        let b = Battery(raw: i.batteryRaw, system: live.battery)
                        Image(systemName: b.symbol).font(.system(size: 12)).foregroundStyle(b.charging ? SS.green : SS.n300).help(b.description)
                    }
                }
                .padding(14)
                HStack(spacing: 8) {
                    Circle().fill(SS.green).frame(width: 8, height: 8)
                    Text(deviceName.replacingOccurrences(of: "Flydigi ", with: "").uppercased()).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                }
                Spacer(minLength: 24)
                if let img = Apex4Render.productImage(deviceId: model.info?.deviceId) {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: 200)
                        .shadow(color: .black.opacity(0.6), radius: 16, y: 10)
                }
                Spacer(minLength: 24)
                Text(model.info.map { "Firmware \($0.firmware) · \(model.connection == .xinput ? "XInput" : "DInput")" } ?? "")
                    .font(.system(size: 12)).foregroundStyle(SS.n300)
                    .padding(.bottom, 18)
            }
            .frame(width: 360, height: 450)
            .background(LinearGradient(colors: [SS.n700.opacity(0.95), SS.n800.opacity(0.9)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SS.brand500.opacity(0.6), lineWidth: 1))
            .shadow(color: SS.brand.opacity(0.25), radius: 30)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open the controller")
    }

    private var emptyCard: some View {
        ZStack {
            // Ghost outline of a controller, like SS4's welcome screen.
            Apex4BodyShape().frame(width: 400, height: 260).opacity(0.5)
            VStack(spacing: 14) {
                Image(systemName: "plus.circle.dashed").font(.system(size: 22)).foregroundStyle(.white)
                Text(model.busy ? "Looking for controllers…" : "Connect a controller").font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                Text("USB-C cable or the charging base's receiver").font(.system(size: 13)).foregroundStyle(SS.n300)
            }
        }
        .frame(height: 300)
    }
}
