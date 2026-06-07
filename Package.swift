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
            name: "PureXMLTests",
            dependencies: ["PureXML"],
            path: "Tests",
            resources: [
                .copy("Fixtures"),
            ],
        ),
    ],
)
