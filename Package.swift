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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.11.1-ruby3.0/RubyVM-xcframework-1.11.1-ruby3.0.zip",
            checksum: "acace72eb68398a5bc05034a86449a51442be1cdd9e390856c1762bd5ca1016d"
        )
    ]
)
