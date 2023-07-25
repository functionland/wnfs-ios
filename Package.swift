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
                //  You can use local path for a faster development
                //  path: "../wnfs-ios-bindings/build/WnfsBindings.xcframework"),
               url: "https://github.com/functionland/wnfs-ios-bindings/releases/download/v1.0.0/cocoapods-bundle.zip",
               checksum: "54fe93527ab3cca6dc5edcac6b82a2c17d3c966138913de92763c4f690ddf753"),
           
            .testTarget(
                name: "WnfsTests",
                dependencies: ["Wnfs"]),
        ]
)
