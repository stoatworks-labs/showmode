// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShowMode",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShowMode",
            path: "Sources/ShowMode",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
