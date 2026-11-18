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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.17.2-ruby3.0/RubyVM-xcframework-1.17.2-ruby3.0.zip",
            checksum: "53ca3268ac7f39e323e2ee3d66036ed7440ddb75787a8b6f2a3423ba5478bd52"
        )
    ]
)
