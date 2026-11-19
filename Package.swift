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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.10-ruby3.0/RubyVM-xcframework-1.17.10-ruby3.0.zip",
            checksum: "fef7e137015082eed717f4cf8722a6f42721b22d9b2cf6439bb371f689cba53c"
        )
    ]
)
