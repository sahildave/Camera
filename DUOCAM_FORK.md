# DuoCam fork delta

This fork adds three small camera seams for DuoCam, plus one fix to inherited upstream behaviour:

- `CameraRearLens` selects the exact rear `AVCaptureDevice.DeviceType` for ultra-wide, wide, or telephoto cameras. `CameraManager.selectRearLens(_:completion:)` and the matching `MCamera.Controller` method report a `Result` exactly once after the serialized input swap succeeds or fails. Unsupported lenses are never replaced with another lens.
- `CameraFrame` and `CameraFrameObserver` expose live frames from the library's existing `AVCaptureVideoDataOutput`. Register with `CameraManager.setFrameObserver(_:queue:)` or the matching controller method. Registration is weak, replaces the previous observer atomically on the capture/session queue, and callback delivery is serial on a queue targeted at the caller-supplied queue while capture delivery is active.

- `CameraManager.setFocusAndExposure(at:focusMode:exposureMode:completion:)` and the matching `MCamera.Controller` method set the focus and exposure point of interest from a normalised point in the preview's coordinate space (`(0, 0)` is the preview's top-left corner; out-of-range values are clamped). The device lock/configure/unlock is serialized on the capture/session queue and the `Result` is reported exactly once. Continuous vs. locked behaviour is expressed with the AVFoundation `FocusMode`/`ExposureMode` enums, defaulting to the one-shot `.autoFocus`/`.autoExpose` pair; a mode or point of interest the active device does not support fails explicitly rather than being silently ignored.

The library owns each `CMSampleBuffer`; it is valid only for the duration of the observer callback. Consumers that work asynchronously must copy the data they need before returning. Frame delivery does no encoding or Vision work.

## Photo capture

The photo path is a fork default, not a knob: the fork opts every capture into the full-quality path rather than exposing capture-settings control. `AVCapturePhotoOutput.maxPhotoQualityPrioritization` is set to `.quality` when the output is added, `maxPhotoDimensions` is raised to the largest of the active format's `supportedMaxPhotoDimensions` (iOS 16+), and per-capture settings mirror the output's own values, so a per-capture request can never exceed the output maximum. Consumers get full-sensor, `.quality`-tier stills by default and cannot lower that from the public API.

`MCameraMedia.getOriginalPhotoData()` returns the unmodified `fileDataRepresentation()` bytes of a captured photo — container, EXIF and any auxiliary depth or matte data intact — alongside the decoded, filtered `UIImage` that `getImage()` already returned. The decoded image is unchanged, so previews and filters keep working and the consumer chooses which representation it needs.

Photo capture failures are observable instead of silent. `MCameraError` gains `photoCaptureSessionNotReady`, `photoCaptureFailed` (the `AVCapturePhotoOutput` delegate reported an error) and `photoPostProcessingFailed` (no data representation, or the image could not be decoded). They are published on the manager as `CameraManager.photoCaptureError` and read back through `MCameraScreen.photoCaptureError`, mirroring how a successful capture is delivered on the published `capturedMedia` attribute; the error clears when a capture starts and when media is delivered, so a repeated identical failure is still observed as a change. The terminal `attributes.error` path is deliberately not reused here: it swaps `MCamera` to its error screen for good, which is right for a permissions failure but would tear the camera down over a single retryable shutter press.

## Inherited bug fix

The accelerometer path reconfigured the frame-output connection on every device-orientation change, even when the camera was locked to portrait, so a consumer tapping raw frames saw the delivered sample buffer flip between portrait and landscape mid-session. `CameraManager.frameOutputOrientation` now resolves to `.portrait` while `orientationLocked` is set, pinning every caller of `configureFrameOutputConnection()`, and the motion manager no longer reconfigures the connection when locked — matching the existing `redrawGrid()`/`updateFrameOrientation()` gating. `attributes.deviceOrientation` keeps tracking the accelerometer, because the photo and video paths and the public `deviceOrientation` accessor consume it and only the frame output is meant to be pinned.

The implementation keeps one capture session and one video-data output, and continues to support the existing front/back camera API. This bounded delta is intended for upstream contribution as a focused API and test seam.
