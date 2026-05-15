# Task 2: Xcode Widget Extension Target

Status: not_started  
Created: 2026-05-14  
Milestone: `milestone-5-watch-complications`

## Objective

Add the `SpektoWatch Complications` Widget Extension target to
`SpektoWatch2.xcodeproj/project.pbxproj` and embed it in the
`SpektoWatch Watch App` target.

## Scope

Modify `project.pbxproj` to add:

1. `PBXFileSystemSynchronizedRootGroup` for `SpektoWatch Complications/` folder.
2. `PBXFileReference` for `SpektoWatch Complications.appex` product.
3. `PBXSourcesBuildPhase`, `PBXFrameworksBuildPhase`, `PBXResourcesBuildPhase`
   for the extension target.
4. `PBXNativeTarget` with `productType =
   "com.apple.product-type.app-extension"`, SDKROOT watchos, linked to the
   synchronized group.
5. `XCBuildConfiguration` (Debug + Release) with:
   - `SDKROOT = watchos`
   - `WATCHOS_DEPLOYMENT_TARGET = 26.2`
   - `PRODUCT_BUNDLE_IDENTIFIER = BrandtAcoustics.SpektoWatch2.watchkitapp.complications`
   - `EXTENSION_ATTRIBUTES = { NSExtension = { ... } }`
   - `GENERATE_INFOPLIST_FILE = YES`
   - `INFOPLIST_KEY_NSExtensionPointIdentifier = com.apple.widgetkit-extension`
6. `XCConfigurationList` for the new target.
7. `PBXTargetDependency` and `PBXContainerItemProxy` in the watch app target.
8. `PBXCopyFilesBuildPhase` (Embed App Extensions) in the watch app target
   embedding the `.appex`.
9. Entry in `PBXProject.targets` and `TargetAttributes`.

## Acceptance

- `xcodebuild build-for-testing -scheme SpektoWatch2` succeeds.
- The `.appex` product is embedded in `SpektoWatch Watch App.app`.

## Non-Goals

- No signing configuration changes (Automatic signing remains).
- No test target for the extension itself.
