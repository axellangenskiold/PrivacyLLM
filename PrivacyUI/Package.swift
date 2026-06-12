// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "PrivacyUI", targets: ["PrivacyUI"]),
    ],
    targets: [
        .target(name: "PrivacyUI"),
    ]
)
