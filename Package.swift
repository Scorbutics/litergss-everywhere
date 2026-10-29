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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.4-ruby3.0/RubyVM-xcframework-1.2.4-ruby3.0.zip",
            checksum: "52929dc5eb386faf9af95d2f2ba9d13c8af199f95720d73042961608e77e3450"
        )
    ]
)
