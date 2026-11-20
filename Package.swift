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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.12-ruby3.0/RubyVM-xcframework-1.17.12-ruby3.0.zip",
            checksum: "bfc71b69109aab2a004ea4880302292fba54638bc4fe528d88975c69a541f9a0"
        )
    ]
)
