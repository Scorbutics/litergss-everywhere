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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.7-ruby3.0/RubyVM-xcframework-1.17.7-ruby3.0.zip",
            checksum: "2fbdd41cbda29996f6728846d58e4a3c8a0a7717a83bfbf3699ccba104826638"
        )
    ]
)
