// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FormBuddy",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/google-ai-edge/mediapipe.git", exact: "1.0.1")
    ],
    targets: [
        .executableTarget(
            name: "FormBuddy",
            dependencies: [
                .product(name: "MediaPipeTasksVision", package: "mediapipe")
            ],
            resources: [.copy("Pose/pose_landmarker_lite.task")]
        ),
        .testTarget(
            name: "FormBuddyTests",
            dependencies: ["FormBuddy"],
            resources: [.copy("Fixtures")]
        )
    ]
)
