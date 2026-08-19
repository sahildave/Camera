//
//  CameraManager+CaptureQueue.swift of MijickCamera
//

import AVKit
import Foundation

final class CameraManagerCaptureQueue: @unchecked Sendable {
    let queue: DispatchQueue

    private var session: any CaptureSession
    private var activeVideoInput: (any CaptureDeviceInput)?
    /// Whether `activeVideoInput` is actually in the session. Derived state would have to read
    /// `session.deviceInputs`, whose `AVCaptureSession` implementation is an all-or-nothing array
    /// cast that yields `[]` if any input does not conform — silently losing the input we hold.
    private var activeVideoInputIsInSession: Bool = false
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

    /// The device the session is actually capturing from, which after an adoption is not
    /// necessarily the one `getCameraInput()` would resolve by position.
    var activeVideoInputDevice: (any CaptureDevice)? {
        queue.sync { activeVideoInput?.device }
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

    /// Adds the video input, or adopts the one the session already carries.
    ///
    /// `setup()` suspends on the permission request, so a caller that replays state onto the
    /// manager (selecting a rear lens, say) can reach the still-empty session first and fill the
    /// single video slot. Setup would then fail `canAddInput` and throw, aborting before the
    /// outputs are attached and leaving `photoOutput` orphaned with no connection. Adopting the
    /// input that is already there keeps the lens the caller picked and lets setup finish.
    func adoptOrAddVideoInput(_ input: (any CaptureDeviceInput)?) throws(MCameraError) {
        do {
            try queue.sync {
                if activeVideoInputIsInSession { return }
                try session.add(input: input)
                activeVideoInput = input
                activeVideoInputIsInSession = true
            }
        } catch let error as MCameraError {
            throw error
        } catch {
            throw .cannotSetupInput
        }
    }

    /// Applies the session preset on the capture queue, so the transaction cannot overlap one
    /// this queue is already running for an input swap.
    func setSessionPreset(_ preset: AVCaptureSession.Preset) {
        queue.sync {
            session.beginConfiguration()
            session.sessionPreset = preset
            session.commitConfiguration()
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
                    activeVideoInputIsInSession = true
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
                    activeVideoInputIsInSession = true
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
