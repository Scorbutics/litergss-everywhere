// swift-tools-version: 5.9
import PackageDescription

// This file is auto-updated by CI on each release.
// To use in your Xcode project: File > Add Package Dependencies >
// https://github.com/Scorbutics/litergss-everywhere.git

let package = Package(
    name: "RubyVM",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "RubyVM", targets: ["RubyVM"])
    ],
    targets: [
        .binaryTarget(
            name: "RubyVM",
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.0.0/RubyVM-xcframework-1.0.0.zip",
            checksum: "PLACEHOLDER"
        )
    ]
)
