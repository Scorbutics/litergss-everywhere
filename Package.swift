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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.8.0-ruby3.0/RubyVM-xcframework-1.8.0-ruby3.0.zip",
            checksum: "799ba042ada26b015216f1c89d0aa6bda49efcee7c82e087c35bededead01550"
        )
    ]
)
