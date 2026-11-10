// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TempMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // Thin C layer over IOKit: SMC, NVMe SMART and the HID temperature sensors.
        .target(
            name: "CSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "TempMonitor",
            dependencies: ["CSensors"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
    ]
)
