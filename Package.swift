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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.1.1/RubyVM-xcframework-1.1.1.zip",
            checksum: "0a5d50058dfc7c63ebc1d6f3b20e141a481384b474fe423119492a2eb9c08aa6"
        )
    ]
)
