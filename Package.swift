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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.5.0-ruby3.0/RubyVM-xcframework-1.5.0-ruby3.0.zip",
            checksum: "3e5d9a2c8379ea1525df9e1d431b5ba611182769d1ba98503c0a46c263be5fec"
        )
    ]
)
