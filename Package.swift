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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.3-ruby3.0/RubyVM-xcframework-1.17.3-ruby3.0.zip",
            checksum: "ee2173c7889a3be4aebec3ed1c73c31bea84be55ee8014eb3f165fc106aaf06b"
        )
    ]
)
