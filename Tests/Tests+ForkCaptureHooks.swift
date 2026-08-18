//
//  Tests+ForkCaptureHooks.swift of MijickCamera
//

import Testing
import AVFoundation
import Foundation
import UIKit
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

    @Test("Photo capture settings request the output's full-quality tier and maximum dimensions")
    func photoCaptureSettingsRequestFullQuality() throws {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        try cameraManager.photoOutput.setup(parent: cameraManager)

        let output = cameraManager.photoOutput.output
        let settings = cameraManager.photoOutput.getPhotoOutputSettings()

        #expect(output.maxPhotoQualityPrioritization == .quality)
        #expect(settings.photoQualityPrioritization == .quality)
        #expect(settings.photoQualityPrioritization.rawValue <= output.maxPhotoQualityPrioritization.rawValue)
        if #available(iOS 16.0, *) {
            #expect(settings.maxPhotoDimensions.width == output.maxPhotoDimensions.width)
            #expect(settings.maxPhotoDimensions.height == output.maxPhotoDimensions.height)
        }
    }

    @Test("Captured media carries the original photo data alongside the decoded image")
    func capturedMediaCarriesOriginalPhotoData() throws {
        let originalPhotoData = Data([0x01, 0x02, 0x03])
        let media = try #require(MCameraMedia(data: UIImage(), originalPhotoData: originalPhotoData))

        #expect(media.getOriginalPhotoData() == originalPhotoData)
        #expect(media.getImage() != nil)
        #expect(MCameraMedia(data: UIImage())?.getOriginalPhotoData() == nil)
    }

    @Test("Photo capture failures are reported instead of being dropped silently")
    func photoCaptureFailuresAreReported() throws {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        try cameraManager.photoOutput.setup(parent: cameraManager)

        cameraManager.photoOutput.capture()
        #expect(cameraManager.photoCaptureError == .photoCaptureSessionNotReady)
        #expect(cameraManager.attributes.capturedMedia == nil)

        cameraManager.photoOutput.processCapturedPhoto(imageData: nil, error: NSError(domain: "DuoCamTests", code: 1))
        #expect(cameraManager.photoCaptureError == .photoCaptureFailed)

        cameraManager.photoOutput.processCapturedPhoto(imageData: Data([0x00, 0x01]), error: nil)
        #expect(cameraManager.photoCaptureError == .photoPostProcessingFailed)
        #expect(cameraManager.attributes.capturedMedia == nil)
    }

    @Test("A processed photo clears the capture error and delivers the original data")
    func processedPhotoDeliversOriginalData() throws {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        try cameraManager.photoOutput.setup(parent: cameraManager)
        cameraManager.photoOutput.processCapturedPhoto(imageData: nil, error: NSError(domain: "DuoCamTests", code: 1))

        let imageData = try #require(makeJPEGData())
        cameraManager.photoOutput.processCapturedPhoto(imageData: imageData, error: nil)

        #expect(cameraManager.photoCaptureError == nil)
        #expect(cameraManager.attributes.capturedMedia?.getOriginalPhotoData() == imageData)
        #expect(cameraManager.attributes.capturedMedia?.getImage() != nil)
    }
}

private func makeJPEGData() -> Data? {
    let renderer = UIGraphicsImageRenderer(size: .init(width: 4, height: 4))
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(.init(x: 0, y: 0, width: 4, height: 4))
    }
    return image.jpegData(compressionQuality: 1)
}
