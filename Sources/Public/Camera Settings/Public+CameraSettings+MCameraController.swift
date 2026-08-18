//
//  Public+CameraSettings+MCameraController.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVFoundation

// MARK: Available Actions
public extension MCamera.Controller {
    /**
     Closes the MCamera.

     See ``MCamera/setCloseMCameraAction(_:)`` for more details.
     */
    func closeMCamera() { mCamera.config.closeMCameraAction() }

    /**
     Opens the Camera Screen.
     */
    func reopenCameraScreen() { mCamera.manager.setCapturedMedia(nil) }

    /**
     Replaces the weak live-frame observer registration.

     Frames are delivered serially on `queue` while capture delivery is active.
     Keep the callback bounded. The registration does not retain `observer`; the
     observer owns its lifetime. A ``CameraFrame`` sample buffer is library-owned
     and is valid only for the duration of its callback, so an asynchronous
     consumer must copy what it needs before returning.
     */
    func setFrameObserver(_ observer: (any CameraFrameObserver)?, queue: DispatchQueue = .main) {
        mCamera.manager.setFrameObserver(observer, queue: queue)
    }

    /**
     Selects an exact physical lens on the rear camera. The completion is called
     exactly once after the input changes or the request fails.
     */
    func selectRearLens(
        _ lens: CameraRearLens,
        completion: @escaping @Sendable (Result<CameraRearLens, MCameraError>) -> Void
    ) {
        mCamera.manager.selectRearLens(lens, completion: completion)
    }

    /**
     Sets the focus and exposure point of interest from a normalised point in the
     preview's coordinate space, where `(0, 0)` is the preview's top-left corner.

     The completion is called exactly once after the active device is configured
     or the request fails. A mode the active device does not support is reported
     as a failure rather than silently ignored.
     */
    func setFocusAndExposure(
        at previewPoint: CGPoint,
        focusMode: AVCaptureDevice.FocusMode = .autoFocus,
        exposureMode: AVCaptureDevice.ExposureMode = .autoExpose,
        completion: @escaping @Sendable (Result<CGPoint, MCameraError>) -> Void
    ) {
        mCamera.manager.setFocusAndExposure(at: previewPoint, focusMode: focusMode, exposureMode: exposureMode, completion: completion)
    }
}
