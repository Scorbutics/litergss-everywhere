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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.5-ruby3.0/RubyVM-xcframework-1.2.5-ruby3.0.zip",
            checksum: "f66f8af19cfa4d48a6db4ed811d5637fcb3cfd6400af3a22006717c4706c69e5"
        )
    ]
)
