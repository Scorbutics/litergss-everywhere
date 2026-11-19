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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.6-ruby3.0/RubyVM-xcframework-1.17.6-ruby3.0.zip",
            checksum: "28bc479c1577ece180d17c26c818940a1c2e9527a438dd0f0df0513d396847ad"
        )
    ]
)
