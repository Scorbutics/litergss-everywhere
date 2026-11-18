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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.16.0-ruby3.0/RubyVM-xcframework-1.16.0-ruby3.0.zip",
            checksum: "6dcaa872f0c37a487ef29c060f40e64fdf8b83c7c0414cafa24207a69860b8f1"
        )
    ]
)
