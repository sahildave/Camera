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

    func selectRearLens(
        _ lens: CameraRearLens,
        completion: @escaping @Sendable (Result<CameraRearLens, MCameraError>, (any CaptureDeviceInput)?) -> Void
    ) {
        queue.async { [self] in
            guard let requestedInput = makeRearInput(lens.deviceType) else {
                completion(.failure(.unsupportedRearLens(lens)), nil)
                return
            }

            let previousInput = activeVideoInput
            if let previousInput { session.remove(input: previousInput) }

            do {
                try session.add(input: requestedInput)
                activeVideoInput = requestedInput
                completion(.success(lens), requestedInput)
            } catch let error as MCameraError {
                if let previousInput { try? session.add(input: previousInput) }
                activeVideoInput = previousInput
                completion(.failure(error), nil)
            } catch {
                if let previousInput { try? session.add(input: previousInput) }
                activeVideoInput = previousInput
                completion(.failure(.cannotSetupInput), nil)
            }
        }
    }
}
