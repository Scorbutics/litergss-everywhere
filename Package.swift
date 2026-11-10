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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.13.0-ruby3.0/RubyVM-xcframework-1.13.0-ruby3.0.zip",
            checksum: "6d77e8633ff5cded981793c5c44868cae3efda09452288726f0bb7a0ca74f1a7"
        )
    ]
)
