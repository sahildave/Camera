//
//  Tests+ForkCaptureHooks.swift of MijickCamera
//

import Testing
import AVFoundation
import Foundation
@testable import MijickCamera

@MainActor @Suite("Fork Capture Hooks", .serialized) struct ForkCaptureHooksTests {
    @Test("Frame output orientation is pinned to portrait while the camera is orientation locked")
    func frameOutputOrientationPinnedWhenOrientationLocked() {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        cameraManager.attributes.deviceOrientation = .landscapeLeft

        cameraManager.attributes.orientationLocked = false
        #expect(cameraManager.frameOutputOrientation == .landscapeLeft)

        cameraManager.attributes.orientationLocked = true
        #expect(cameraManager.frameOutputOrientation == .portrait)
        #expect(cameraManager.attributes.deviceOrientation == .landscapeLeft)
    }
}
