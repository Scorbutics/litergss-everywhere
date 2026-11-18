// swift-tools-version: 5.9
import PackageDescription

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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.15.2-ruby3.0/RubyVM-xcframework-1.15.2-ruby3.0.zip",
            checksum: "a07c82c4ca9e90e48a9f5c02cd12d3ac8adb44a5aa021c14d46189cfdac76599"
        )
    ]
)
