// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PureXML",
    products: [
        .library(
            name: "PureXML",
            targets: ["PureXML"],
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PureXML",
            path: "Sources",
        ),
        .testTarget(
            name: "PureXMLPublicAPITests",
            dependencies: ["PureXML"],
            path: "PublicAPITests",
        ),
        .testTarget(
            name: "PureXMLTests",
            dependencies: ["PureXML"],
            path: "Tests",
            // The vendored XSTS archive is consumed off-disk via XSTS_ROOT, never
            // from the test bundle, so keep it out of the copied resources.
            exclude: ["Fixtures/xsts"],
            resources: [
                .copy("Fixtures"),
            ],
        ),
    ],
)
