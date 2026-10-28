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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.1.0/RubyVM-xcframework-1.1.0.zip",
            checksum: "d3491bc3d2595dfb31195343b149802bc44342529e829d01a610b227c2a8055b"
        )
    ]
)
