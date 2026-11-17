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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.15.0-ruby3.0/RubyVM-xcframework-1.15.0-ruby3.0.zip",
            checksum: "14629cae51150ca83e3167ae90478d2f7dbd629d2fead2a82cd182f75b9fe492"
        )
    ]
)
