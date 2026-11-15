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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.14.1-ruby3.0/RubyVM-xcframework-1.14.1-ruby3.0.zip",
            checksum: "67fb6337b207069e04429a560088e62aff33426113bbd2e358a0dcec44ad8530"
        )
    ]
)
