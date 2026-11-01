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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.9.0-ruby3.0/RubyVM-xcframework-1.9.0-ruby3.0.zip",
            checksum: "7f315be76a92fc3da344c5e4c5531eac329d5d47ccc99b267ed13de1527b160e"
        )
    ]
)
