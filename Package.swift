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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.15.1-ruby3.0/RubyVM-xcframework-1.15.1-ruby3.0.zip",
            checksum: "612ebe06a7d623c38e51c1b75361a6f37dca0cac0d083859adbe6b29219090a3"
        )
    ]
)
