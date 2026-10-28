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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.1/RubyVM-xcframework-1.2.1.zip",
            checksum: "e70b6032f840ff063d5648266787d8519c6b0fa06cd2cac04875420c969c8dd4"
        )
    ]
)
