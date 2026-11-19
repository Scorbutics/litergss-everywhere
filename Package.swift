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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.9-ruby3.0/RubyVM-xcframework-1.17.9-ruby3.0.zip",
            checksum: "ee2d1b4c11234ebe572d93867125c28c90cfd58dab695c8f2d82039b56afaa95"
        )
    ]
)
