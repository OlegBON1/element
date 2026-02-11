// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Element",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Element",
            path: "Element",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
            ],
            resources: [
                .copy("Resources/element-sdk.js"),
            ]
        ),
    ]
)
