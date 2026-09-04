// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bmoni_embedded_sdk",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "bmoni-embedded-sdk", targets: ["bmoni_embedded_sdk","BMONISigner"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "bmoni_embedded_sdk",
            dependencies: [],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        ),
         .binaryTarget(
            name: "BMONISigner",
            url: "https://internal-asset-distribution.s3.eu-north-1.amazonaws.com/BMONISigner.1.0.0.xcframework.zip",
            checksum: "eccb5466ebb62cb5f5d2c7ff05ae6681d8bbc5c7f92595c523b9462385e2eefc"
        ),
    ]
)
