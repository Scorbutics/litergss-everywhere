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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.10-ruby3.0/RubyVM-xcframework-1.2.10-ruby3.0.zip",
            checksum: "443872202bec5f48e7690ce37edbd8dbce618269719fa65ef593a23c71ec8813"
        )
    ]
)
