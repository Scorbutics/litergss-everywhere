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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.9-ruby3.0/RubyVM-xcframework-1.2.9-ruby3.0.zip",
            checksum: "ba7c5dfafdbd49cd2f6a141eb5608f2a22fdd8ddffc00adb324e852ccf6fd7d5"
        )
    ]
)
