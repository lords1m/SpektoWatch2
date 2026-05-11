# Task 4: Recording Photo Attachment

Status: completed  
Created: 2026-05-12  
Completed: 2026-05-12  
Milestone: `milestone-3-dashboard-and-recording-polish`

## Objective

Allow users to attach photos to a recording and view them in the detail view.

## Context

- `Recording.photoFileNames: [String]` already exists in the model.
- The model stores file names, not URLs; photos should be saved to the app's
  Documents directory alongside audio and measurement files.
- No photo attachment UI exists yet in `RecordingDetailView`.

## Scope

### Photo storage

Reuse or extend the file-naming convention already used for `.wav` /
`.spekto` files. Save each photo as a JPEG under:
`<Documents>/Photos/<recordingID>-<uuid>.jpg`

Helper (can go in `RecordingManager` or a small `PhotoStorage` helper):

```swift
func savePhoto(_ image: UIImage, for recordingID: UUID) throws -> String
func photoURL(fileName: String) -> URL
func deletePhoto(fileName: String)
```

### `SpektoWatch2/Views/RecordingDetailView.swift`

In the overview tab, add a **Photos** section that:

1. Shows existing attached photos as a horizontal scroll row of thumbnails
   (using `AsyncImage` or `Image(uiImage:)`).
2. Has an "Foto hinzufügen" button that presents a `PHPickerViewController`
   (iOS 14+) allowing single image selection.
3. On selection, saves the image and appends the file name to
   `recording.photoFileNames`, then persists via `RecordingManager`.
4. Allows deleting a photo via long-press or swipe (removes from disk and
   from `recording.photoFileNames`).

### `SpektoWatch2/RecordingManager.swift`

Ensure `updateRecording(_:)` (added in task 3 if missing) also saves changes
to `photoFileNames`.

## Acceptance

- A photo can be selected from the photo library and appears as a thumbnail
  in the detail view.
- The photo persists after dismissing and reopening the recording.
- Deleting a photo removes it from the display and from disk.
- A recording with no photos shows no photos section crash.
- `NSPhotoLibraryUsageDescription` is present in `Info.plist`.

## Non-Goals

- No camera capture in this task (photo library only).
- No photo editing or annotation.
- No iCloud sync or sharing of photos from this view.
