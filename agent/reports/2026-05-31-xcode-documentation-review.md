# Xcode Documentation Review

Date: 2026-05-31

## Scope

Three parallel read-only reviews covered TestFlight copy, repository
documentation, Xcode metadata, visible UI text, permission prompts, and
accessibility labels.

## Completed

- Added canonical external TestFlight copy with separate stable beta
  description and build-specific `What to Test`.
- Updated microphone and motion permission prompts for iOS and watchOS.
- Removed `TestPlan.xctestplan` from the production app resources phase.
- Standardized the visible app and Live Activity extension display name to
  `SpektoWatch`.
- Removed an obsolete shared-scheme LambdaTest post-build hook containing a
  hardcoded access key. The environment-variable-based scripts under
  `lambdatest/` remain available.
- Removed a tracked generated distribution export containing sensitive
  packaging metadata and added an ignore rule for future timestamped exports.
- Refreshed architecture, TestFlight, screenshot, watch-plan, and test-concept
  documentation.
- Removed unsupported standards-conformance wording from the bandstop guide and
  clarified the psychoacoustic loudness approximation.
- Fixed visible German wording and added accessibility labels to core
  image-only controls.

## Remaining

- Add string catalogs (`Localizable.xcstrings` and localized Info.plist
  permission copy) before supporting multiple UI languages. The current app is
  primarily German but still contains intentional and incidental English text.
- Decide whether the unreferenced legacy
  `SpektoWatch Watch App/Watch-Info.plist` should be removed after a target
  membership check in Xcode.
- Rotate the removed LambdaTest access key. Deleting it from the current
  workspace does not remove it from Git history.
- Consider purging generated distribution exports and the exposed key from Git
  history before sharing the repository outside the trusted team.

## Verification

- `plutil -lint` passed for the app, watch app, Live Activity extension, and
  complication plists.
- `xmllint --noout` passed for the shared iOS scheme.
- `xcodebuild -list -project SpektoWatch2.xcodeproj` resolved packages and
  listed all targets and schemes.
- `xcodebuild -project SpektoWatch2.xcodeproj -scheme SpektoWatch2
  -configuration Debug -destination 'platform=iOS Simulator,...' build`
  succeeded, including the watch app, complications, and Live Activity
  extension.
- `./agent/scripts/acp-validate` passed.
