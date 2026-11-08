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
            url: "https://github.com/Scorbutics/litergss-everywhere/releases/download/v1.12.2-ruby3.0/RubyVM-xcframework-1.12.2-ruby3.0.zip",
            checksum: "c1296421342ef3c879fabfdd6bda92792fa4a7675996ab8f7884aff0b9db8991"
        )
    ]
)
