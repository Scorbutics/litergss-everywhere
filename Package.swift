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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.7-ruby3.0/RubyVM-xcframework-1.17.7-ruby3.0.zip",
            checksum: "c7e412130b1fee629186aa2099e2fb615c65416db553ef75b2662ed99c23f768"
        )
    ]
)
