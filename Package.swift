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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.12.0-ruby3.0/RubyVM-xcframework-1.12.0-ruby3.0.zip",
            checksum: "1b8fd4ba4fa2fe1f3dff033119ae1ac824357599d1ae441552388b93de9670c3"
        )
    ]
)
