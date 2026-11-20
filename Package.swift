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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.11-ruby3.0/RubyVM-xcframework-1.17.11-ruby3.0.zip",
            checksum: "6f7849027ea0dd90c561fc91351cc07422e7e8a9d53b0938163007d6e64b9db5"
        )
    ]
)
