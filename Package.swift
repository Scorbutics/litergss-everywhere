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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.0/RubyVM-xcframework-1.2.0.zip",
            checksum: "c0e9b3a4c351b8bb44a5f26d63ad7dc5cafc95245a8c786a9d6e9f1983a10b0d"
        )
    ]
)
