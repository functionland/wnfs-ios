// swift-tools-version:5.3
import PackageDescription
import Foundation
let package = Package(
        name: "Wnfs",
        platforms: [
            .iOS(.v13), 
        ],
        products: [
            .library(
                name: "Wnfs",
                targets: ["Wnfs"]),
            .library(
                name: "WnfsBindings",
                targets: ["WnfsBindings"]),
        ],
        targets: [
            .target(
                name: "Wnfs",
                dependencies: ["WnfsBindings",]),
            .binaryTarget(
                name: "WnfsBindings",
//                 You can use local path for faster development
                 path: "../wnfs-ios-bindings/build/WnfsBindings.xcframework"),
//                url: "https://github.com/functionland/wnfs-ios-bindings/releases/download/v0.1.6/swift-bundle.zip",
//                checksum: "07cd3d130a0db69a054fa631059c165d2c46c878a8a668044d4f06006eb729fe"),
           
            .testTarget(
                name: "WnfsTests",
                dependencies: ["Wnfs"]),
        ]
)
