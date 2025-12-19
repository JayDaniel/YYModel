// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "YYModel",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "YYModel",
            targets: ["YYModel"]
        )
    ],
    targets: [
        .target(
            name: "YYModel",
            path: "YYModel",
            publicHeadersPath: ".",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
