//
//  CameraManager+CaptureQueue.swift of MijickCamera
//

import AVKit
import Foundation

final class CameraManagerCaptureQueue: @unchecked Sendable {
    let queue: DispatchQueue

    private var session: any CaptureSession
    private var activeVideoInput: (any CaptureDeviceInput)?
    private let makeRearInput: @Sendable (AVCaptureDevice.DeviceType) -> (any CaptureDeviceInput)?

    init(
        session: any CaptureSession,
        activeVideoInput: (any CaptureDeviceInput)?,
        makeRearInput: @escaping @Sendable (AVCaptureDevice.DeviceType) -> (any CaptureDeviceInput)?
    ) {
        self.queue = .init(label: "com.mijick.camera.capture-session", qos: .userInitiated)
        self.session = session
        self.activeVideoInput = activeVideoInput
        self.makeRearInput = makeRearInput
    }
}

// MARK: Session Lifetime
extension CameraManagerCaptureQueue {
    func startRunning() {
        queue.sync {
            session.startRunning()
        }
    }

    func stopRunningAndReturnNewSession() -> any CaptureSession {
        queue.sync {
            let newSession = session.stopRunningAndReturnNewInstance()
            session = newSession
            return newSession
        }
    }

    func setActiveVideoInput(_ input: (any CaptureDeviceInput)?) {
        queue.sync {
            activeVideoInput = input
        }
    }
}

// MARK: Session Operations
extension CameraManagerCaptureQueue {
    func add(input: (any CaptureDeviceInput)?) throws(MCameraError) {
        do {
            try queue.sync {
                try session.add(input: input)
            }
        } catch let error as MCameraError {
            throw error
        } catch {
            throw .cannotSetupInput
        }
    }

    func add(output: AVCaptureOutput?) throws(MCameraError) {
        do {
            try queue.sync {
                try session.add(output: output)
            }
        } catch let error as MCameraError {
            throw error
        } catch {
            throw .cannotSetupOutput
        }
    }

    func replaceActiveVideoInput(with input: (any CaptureDeviceInput)?) throws(MCameraError) {
        do {
            try queue.sync {
                session.beginConfiguration()
                defer { session.commitConfiguration() }

                let previousInput = activeVideoInput
                if let previousInput { session.remove(input: previousInput) }

                do {
                    try session.add(input: input)
                    activeVideoInput = input
                } catch {
                    if let previousInput { try? session.add(input: previousInput) }
                    activeVideoInput = previousInput
                    throw error
                }
            }
        } catch let error as MCameraError {
            throw error
        } catch {
            throw .cannotSetupInput
        }
    }

    func setFocusAndExposure(
        at pointOfInterest: CGPoint,
        focusMode: AVCaptureDevice.FocusMode?,
        exposureMode: AVCaptureDevice.ExposureMode?,
        completion: @escaping @Sendable (Result<CGPoint, MCameraError>) -> Void
    ) {
        queue.async { [self] in
            guard let device = activeVideoInput?.device else { return completion(.failure(.cannotSetupInput)) }
            if let focusMode {
                guard device.isFocusPointOfInterestSupported else { return completion(.failure(.unsupportedPointOfInterest)) }
                guard device.isFocusModeSupported(focusMode) else { return completion(.failure(.unsupportedFocusMode(focusMode))) }
            }
            if let exposureMode {
                guard device.isExposurePointOfInterestSupported else { return completion(.failure(.unsupportedPointOfInterest)) }
                guard device.isExposureModeSupported(exposureMode) else { return completion(.failure(.unsupportedExposureMode(exposureMode))) }
            }

            do { try device.lockForConfiguration() } catch { return completion(.failure(.cannotLockDeviceForConfiguration)) }
            if let focusMode {
                device.focusPointOfInterest = pointOfInterest
                device.focusMode = focusMode
            }
            if let exposureMode {
                device.exposurePointOfInterest = pointOfInterest
                device.exposureMode = exposureMode
            }
            device.unlockForConfiguration()

            completion(.success(pointOfInterest))
        }
    }

    func selectRearLens(
        _ lens: CameraRearLens,
        completion: @escaping @Sendable (Result<CameraRearLens, MCameraError>, (any CaptureDeviceInput)?) -> Void
    ) {
        queue.async { [self] in
            guard let requestedInput = makeRearInput(lens.deviceType) else {
                completion(.failure(.unsupportedRearLens(lens)), nil)
                return
            }

            // The swap runs inside a single configuration transaction, and the completion is called
            // only after it commits, so the session has settled its active format for the new input
            // before any observer reads the device.
            let outcome: (Result<CameraRearLens, MCameraError>, (any CaptureDeviceInput)?) = {
                session.beginConfiguration()
                defer { session.commitConfiguration() }

                let previousInput = activeVideoInput
                if let previousInput { session.remove(input: previousInput) }

                do {
                    try session.add(input: requestedInput)
                    activeVideoInput = requestedInput
                    return (.success(lens), requestedInput)
                } catch let error as MCameraError {
                    if let previousInput { try? session.add(input: previousInput) }
                    activeVideoInput = previousInput
                    return (.failure(error), nil)
                } catch {
                    if let previousInput { try? session.add(input: previousInput) }
                    activeVideoInput = previousInput
                    return (.failure(.cannotSetupInput), nil)
                }
            }()

            completion(outcome.0, outcome.1)
        }
    }
}
