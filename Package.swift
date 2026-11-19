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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.5-ruby3.0/RubyVM-xcframework-1.17.5-ruby3.0.zip",
            checksum: "af3497a63c74df2f0d8d4612daadc50a34d8b301fa35c2e02adb59855a75a9bb"
        )
    ]
)
