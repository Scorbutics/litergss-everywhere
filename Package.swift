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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.3.0-ruby3.0/RubyVM-xcframework-1.3.0-ruby3.0.zip",
            checksum: "a55271d9dc85b46df92a6ab2ea7bcaee40fbcbe0374fc16e7cb5caa7a6535a42"
        )
    ]
)
