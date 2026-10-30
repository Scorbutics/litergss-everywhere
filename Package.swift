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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.2.11-ruby3.0/RubyVM-xcframework-1.2.11-ruby3.0.zip",
            checksum: "99753c7d8b73ed7c396c78b82157710715c692ed3a64066344ab58c12cc246be"
        )
    ]
)
