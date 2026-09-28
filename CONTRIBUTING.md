# Contributing

Thanks for your interest in improving FormBuddy!

FormBuddy is a native mobile app: the iOS client lives in `FormBuddy/` and is
built from `project.yml` with XcodeGen. See `AGENTS.md` for the build commands
and the layout of the shared analysis core.

## Development setup

```bash
xcodegen generate        # regenerate FormBuddy.xcodeproj (runs pod install)
open FormBuddy.xcworkspace
```

Always work in `FormBuddy.xcworkspace`, never `FormBuddy.xcodeproj` — the
MediaPipe CocoaPods products only resolve in the workspace.

## Adding a new exercise analyzer

1. Add a type in `FormBuddy/AnalysisCore/` conforming to the `ExerciseAnalyzer`
   protocol (`analyze(_ frames: [PoseFrame]) -> ExerciseReport`). See
   `FormBuddy/AnalysisCore/SquatAnalyzer.swift` for the pattern.
2. Register it wherever the app selects an analyzer so the UI can offer it.
3. Add tests in `Tests/FormBuddyTests/` using synthetic landmark trajectories
   (see `SquatAnalyzerTests.swift` for the pattern).
4. Update the README's supported-exercises list.

## Guidelines

- Keep analyzers pure: no I/O and no MediaPipe imports — work on landmark
  arrays. Pose and segmentation live in `FormBuddy/Pose/`.
- Every analyzer needs tests with synthetic trajectories before it lands.
- Run the full suite (`make ios-test`) before committing.
