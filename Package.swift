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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.10.0-ruby3.0/RubyVM-xcframework-1.10.0-ruby3.0.zip",
            checksum: "13e95158a08e94770f010f87fe3317afe9d7d9b4a38be8e49d27ae70f29b7063"
        )
    ]
)
