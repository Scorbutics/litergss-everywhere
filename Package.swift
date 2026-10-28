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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.2-ruby3.0/RubyVM-xcframework-1.2.2-ruby3.0.zip",
            checksum: "10d7b6bb31b45f86167157b386c457ab39b772da7086d5ac4804c2550bc0fe5f"
        )
    ]
)
