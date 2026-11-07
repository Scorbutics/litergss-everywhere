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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.12.1-ruby3.0/RubyVM-xcframework-1.12.1-ruby3.0.zip",
            checksum: "f570f8e1bcdef56963655792f470cc006e3a827c46d67a0df8a20db981335843"
        )
    ]
)
