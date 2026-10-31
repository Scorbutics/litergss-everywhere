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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.4.0-ruby3.0/RubyVM-xcframework-1.4.0-ruby3.0.zip",
            checksum: "5c37d1bc0167da737c8a322c3214f332a187e57712113e08293caa0770d232eb"
        )
    ]
)
