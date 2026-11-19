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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.8-ruby3.0/RubyVM-xcframework-1.17.8-ruby3.0.zip",
            checksum: "39d492cf1f9eda4b2cffd13932240a6af392c598189b8cb52585cfad302092ca"
        )
    ]
)
