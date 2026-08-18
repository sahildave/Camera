//
//  Tests+ForkCaptureHooks.swift of MijickCamera
//

import Testing
import AVFoundation
import Combine
import Foundation
import SwiftUI
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

    @Test("Full-quality capture settings are recomputed when the active video input changes")
    func fullQualityCaptureRecomputedOnInputChange() async throws {
        let session = MockCaptureSession()
        let cameraManager = CameraManager(
            captureSession: session,
            captureDeviceInputType: MockDeviceInput.self
        )
        try session.add(input: cameraManager.backCameraInput)
        try cameraManager.photoOutput.setup(parent: cameraManager)

        let wideDeviceID = try #require(cameraManager.backCameraInput?.device.uniqueID)
        #expect(cameraManager.photoOutput.fullQualityCaptureDeviceID == wideDeviceID)

        let result = await withCheckedContinuation { continuation in
            cameraManager.selectRearLens(.telephoto) { continuation.resume(returning: $0) }
        }
        let telephotoDevice = try #require(cameraManager.backCameraInput?.device)

        #expect(result == .success(.telephoto))
        #expect(telephotoDevice.deviceType == .builtInTelephotoCamera)
        #expect(telephotoDevice.uniqueID != wideDeviceID)
        #expect(cameraManager.photoOutput.fullQualityCaptureDeviceID == telephotoDevice.uniqueID)
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

    @Test("A repeated identical capture failure is still published as a change")
    func repeatedCaptureFailureIsPublishedAsChange() throws {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        try cameraManager.photoOutput.setup(parent: cameraManager)

        let recorder = ErrorRecorder()
        let cancellable = cameraManager.$attributes
            .map(\.photoCaptureError)
            .removeDuplicates()
            .sink { recorder.record($0) }
        defer { cancellable.cancel() }

        cameraManager.photoOutput.capture()
        cameraManager.photoOutput.capture()

        #expect(cameraManager.photoCaptureError == .photoCaptureSessionNotReady)
        #expect(recorder.values == [nil, .photoCaptureSessionNotReady, nil, .photoCaptureSessionNotReady])
    }

    @Test("A device supporting only one of focus and exposure serves the half it supports")
    func halfSupportedPointOfInterestIsServed() async throws {
        let session = MockCaptureSession()
        let cameraManager = CameraManager(
            captureSession: session,
            captureDeviceInputType: MockDeviceInput.self
        )
        try session.add(input: cameraManager.backCameraInput)
        let device = try #require(cameraManager.backCameraInput?.device as? MockCaptureDevice)
        device.isFocusPointOfInterestSupported = false

        let exposureOnly = await withCheckedContinuation { continuation in
            cameraManager.setFocusAndExposure(at: .init(x: 0.25, y: 0.75), focusMode: nil, exposureMode: .continuousAutoExposure) { continuation.resume(returning: $0) }
        }
        #expect(exposureOnly == .success(.init(x: 0.75, y: 0.75)))
        #expect(device.exposurePointOfInterest == CGPoint(x: 0.75, y: 0.75))
        #expect(device.exposureMode == .continuousAutoExposure)
        #expect(device.focusPointOfInterest == .zero)
        #expect(device.focusMode == .autoFocus)

        let bothHalves = await withCheckedContinuation { continuation in
            cameraManager.setFocusAndExposure(at: .init(x: 0, y: 0), focusMode: .autoFocus, exposureMode: .continuousAutoExposure) { continuation.resume(returning: $0) }
        }
        #expect(bothHalves == .failure(.unsupportedPointOfInterest))
        #expect(device.exposurePointOfInterest == CGPoint(x: 0.75, y: 0.75))
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

    @Test("A camera screen reads the original photo data without a captured media screen")
    func cameraScreenExposesCapturedPhotoData() throws {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        try cameraManager.photoOutput.setup(parent: cameraManager)

        let screen = ForkTestCameraScreen(cameraManager: cameraManager, namespace: Namespace().wrappedValue, closeMCameraAction: {})
        #expect(screen.capturedPhotoData == nil)

        let imageData = try #require(makeJPEGData())
        cameraManager.photoOutput.processCapturedPhoto(imageData: imageData, error: nil)
        #expect(screen.capturedPhotoData == imageData)

        cameraManager.setCapturedMedia(nil)
        #expect(screen.capturedPhotoData == nil)
    }

    @Test("Setting focus and exposure configures the active device once, in device coordinates")
    func setFocusAndExposureConfiguresActiveDevice() async throws {
        let session = MockCaptureSession()
        let cameraManager = CameraManager(
            captureSession: session,
            captureDeviceInputType: MockDeviceInput.self
        )
        try session.add(input: cameraManager.backCameraInput)
        let device = try #require(cameraManager.backCameraInput?.device as? MockCaptureDevice)

        let completionCounter = CompletionCounter()
        let result = await withCheckedContinuation { continuation in
            cameraManager.setFocusAndExposure(at: .init(x: 0.25, y: 0.75), focusMode: .continuousAutoFocus, exposureMode: .continuousAutoExposure) { result in
                completionCounter.increment()
                continuation.resume(returning: result)
            }
        }

        #expect(result == .success(.init(x: 0.75, y: 0.75)))
        #expect(completionCounter.value == 1)
        #expect(device.focusPointOfInterest == CGPoint(x: 0.75, y: 0.75))
        #expect(device.exposurePointOfInterest == CGPoint(x: 0.75, y: 0.75))
        #expect(device.focusMode == .continuousAutoFocus)
        #expect(device.exposureMode == .continuousAutoExposure)
    }

    @Test("Focus and exposure requests the active device cannot serve fail explicitly")
    func unsupportedFocusAndExposureRequestsFail() async throws {
        let session = MockCaptureSession()
        let cameraManager = CameraManager(
            captureSession: session,
            captureDeviceInputType: MockDeviceInput.self
        )
        try session.add(input: cameraManager.backCameraInput)
        let device = try #require(cameraManager.backCameraInput?.device as? MockCaptureDevice)
        device.supportedFocusModes = [.continuousAutoFocus]
        device.supportedExposureModes = [.continuousAutoExposure]

        let unsupportedFocusMode = await withCheckedContinuation { continuation in
            cameraManager.setFocusAndExposure(at: .zero, focusMode: .locked, exposureMode: .continuousAutoExposure) { continuation.resume(returning: $0) }
        }
        #expect(unsupportedFocusMode == .failure(.unsupportedFocusMode(.locked)))

        let unsupportedExposureMode = await withCheckedContinuation { continuation in
            cameraManager.setFocusAndExposure(at: .zero, focusMode: .continuousAutoFocus, exposureMode: .locked) { continuation.resume(returning: $0) }
        }
        #expect(unsupportedExposureMode == .failure(.unsupportedExposureMode(.locked)))

        device.isFocusPointOfInterestSupported = false
        let unsupportedPointOfInterest = await withCheckedContinuation { continuation in
            cameraManager.setFocusAndExposure(at: .zero, focusMode: .continuousAutoFocus, exposureMode: .continuousAutoExposure) { continuation.resume(returning: $0) }
        }
        #expect(unsupportedPointOfInterest == .failure(.unsupportedPointOfInterest))

        #expect(device.focusPointOfInterest == .zero)
        #expect(device.focusMode == .autoFocus)
        #expect(device.exposureMode == .continuousAutoExposure)
    }
}

private struct ForkTestCameraScreen: MCameraScreen {
    @ObservedObject var cameraManager: CameraManager
    let namespace: Namespace.ID
    let closeMCameraAction: () -> ()

    var body: some View { EmptyView() }
}

private final class ErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MCameraError?] = []

    var values: [MCameraError?] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ error: MCameraError?) {
        lock.lock()
        recorded.append(error)
        lock.unlock()
    }
}

private final class CompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
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
