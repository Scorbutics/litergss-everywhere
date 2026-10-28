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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.3-ruby3.0/RubyVM-xcframework-1.2.3-ruby3.0.zip",
            checksum: "9713e569246bdc3f976b54e8d7e0cc9e122514df66fc2ff5b1df447beed78676"
        )
    ]
)
