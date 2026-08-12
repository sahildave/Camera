//
//  Public+CameraSettings+MCameraController.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import Foundation

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
}
