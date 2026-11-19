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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.4-ruby3.0/RubyVM-xcframework-1.17.4-ruby3.0.zip",
            checksum: "8c9744fb7f7d81b467be568372b54208e0bcb9f554667ddf83de84416b11397a"
        )
    ]
)
