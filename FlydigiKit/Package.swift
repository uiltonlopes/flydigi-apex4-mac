// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlydigiKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FlydigiKit", targets: ["FlydigiKit"]),
        .executable(name: "apex4", targets: ["apex4"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Pure protocol layer: packet framing, blobs, LVGL encoder, upload plan. No I/O.
        .target(name: "FlydigiKit"),
        // macOS transports (IOHIDManager for DInput, IOUSBHost for XInput) + device session.
        .target(
            name: "FlydigiTransport",
            dependencies: ["FlydigiKit"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost")]
        ),
        .executableTarget(
            name: "apex4",
            dependencies: [
                "FlydigiKit", "FlydigiTransport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "FlydigiKitTests",
            dependencies: ["FlydigiKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
