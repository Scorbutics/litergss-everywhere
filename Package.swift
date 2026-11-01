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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.6.0-ruby3.0/RubyVM-xcframework-1.6.0-ruby3.0.zip",
            checksum: "db5b58b22675a9a1c038ab7347209b876897e8759d07e6bbe29be470bae1d17c"
        )
    ]
)
