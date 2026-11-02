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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.11.0-ruby3.0/RubyVM-xcframework-1.11.0-ruby3.0.zip",
            checksum: "b23a08e8502b7db8c50789798ebbe5c1e705bddbf7214f0e82a967e824275b8a"
        )
    ]
)
