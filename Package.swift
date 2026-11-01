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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.7.0-ruby3.0/RubyVM-xcframework-1.7.0-ruby3.0.zip",
            checksum: "2733fc8f424e7bdb883be4b7c7a4d54c1ab4d511713673285d4a03eda67fcab4"
        )
    ]
)
