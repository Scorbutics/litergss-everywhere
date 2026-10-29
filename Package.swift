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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.6-ruby3.0/RubyVM-xcframework-1.2.6-ruby3.0.zip",
            checksum: "3bffbecfd6b6b8a87a3de98f05d716cb087beabc9a4c20ea19d3db1d0abe676b"
        )
    ]
)
