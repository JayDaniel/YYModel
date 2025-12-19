// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "YYModel",
    platforms: [
        .iOS(.v14),
        .macOS(.v10_15),
        .tvOS(.v12),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "YYModel",
            targets: ["YYModel"]
        ),
    ],
    targets: [
        .target(
            name: "YYModel",
            dependencies: [],
            path: "YYModel",
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            publicHeadersPath: "."
        ),
    ]
)
