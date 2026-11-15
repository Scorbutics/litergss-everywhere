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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.14.0-ruby3.0/RubyVM-xcframework-1.14.0-ruby3.0.zip",
            checksum: "056bcf02ae2eca6e36592a51aef0ecc40afd22f4fb4a4e18e8c85ea663855f2f"
        )
    ]
)
