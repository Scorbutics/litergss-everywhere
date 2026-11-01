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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.9.1-ruby3.0/RubyVM-xcframework-1.9.1-ruby3.0.zip",
            checksum: "9678cf1180821205b95258cc07f6a8389055b1e04e72108d390fdb0533a54479"
        )
    ]
)
