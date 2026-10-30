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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.8-ruby3.0/RubyVM-xcframework-1.2.8-ruby3.0.zip",
            checksum: "bebcf7d9460b6b0ed1407bd5c3558ccd7f1ca36724747d7c7de0fc11f201c396"
        )
    ]
)
