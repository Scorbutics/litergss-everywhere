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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.0-ruby3.0/RubyVM-xcframework-1.17.0-ruby3.0.zip",
            checksum: "c955598f614a45b6ac132fdc260d1c8d3b2c95272e3b859c164eb651266a6de4"
        )
    ]
)
