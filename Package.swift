// swift-tools-version:5.3
import PackageDescription
import Foundation
let package = Package(
        name: "WnfsSwift",
        platforms: [
            .iOS(.v8), 
            .macOS(.v11)
        ],
        products: [
            .library(
                name: "WnfsSwift",
                targets: ["WnfsSwift"]),
            .library(
                name: "WnfsBindings",
                targets: ["WnfsBindings"]),
        ],
        dependencies: [
            // Dependencies declare other packages that this package depends on.
            .package(url: "https://github.com/swift-libp2p/swift-cid.git", .upToNextMajor(from: "0.0.1")),
        ],
        targets: [
            .target(
                name: "WnfsSwift",
                dependencies: ["WnfsBindings", .product(name: "CID", package: "swift-cid"),]),
            .binaryTarget(
                name: "WnfsBindings",
                // You can use local path for faster development
                // path: "../build/WnfsBindings.xcframework"),
                url: "https://github.com/functionland/wnfs-swift-bindings/releases/download/v0.1.2/swift-bundle.zip",
                checksum: "47c48b73eb614fc4643f9fbc35d12d990e954dc3ac3a86e6480c85ce374a6987"),
           
            .testTarget(
                name: "WnfsSwiftTests",
                dependencies: ["WnfsSwift"]),
        ]
)
