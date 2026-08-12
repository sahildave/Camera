# DuoCam fork delta

This fork adds two small camera seams for DuoCam:

- `CameraRearLens` selects the exact rear `AVCaptureDevice.DeviceType` for ultra-wide, wide, or telephoto cameras. `CameraManager.selectRearLens(_:completion:)` and the matching `MCamera.Controller` method report a `Result` exactly once after the serialized input swap succeeds or fails. Unsupported lenses are never replaced with another lens.
- `CameraFrame` and `CameraFrameObserver` expose live frames from the library's existing `AVCaptureVideoDataOutput`. Register with `CameraManager.setFrameObserver(_:queue:)` or the matching controller method. Registration is weak, replaces the previous observer atomically on the capture/session queue, and callback delivery is serial on a queue targeted at the caller-supplied queue while capture delivery is active.

The library owns each `CMSampleBuffer`; it is valid only for the duration of the observer callback. Consumers that work asynchronously must copy the data they need before returning. Frame delivery does no encoding or Vision work.

The implementation keeps one capture session and one video-data output, and continues to support the existing front/back camera API. This bounded delta is intended for upstream contribution as a focused API and test seam.
