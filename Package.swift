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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.16.1-ruby3.0/RubyVM-xcframework-1.16.1-ruby3.0.zip",
            checksum: "1eab981cac1f96572caa50470a15a69e449a1f0e7cb5c091a0ac388ebd5b994c"
        )
    ]
)
