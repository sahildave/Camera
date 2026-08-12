//
//  CameraManager+FrameOutput.swift of MijickCamera
//

@preconcurrency import AVKit
import Foundation

final class CameraManagerFrameOutput: NSObject, @unchecked Sendable {
    let output: AVCaptureVideoDataOutput

    weak var cameraManager: CameraManager?
    weak var preview: CameraMetalView?

    private let sessionQueue: DispatchQueue
    private let stateLock = NSLock()
    private let registrationKey = DispatchSpecificKey<UInt8>()
    private var observerBox: WeakCameraFrameObserverBox?
    private var callbackQueue: DispatchQueue?
    private var registrationID: UInt = 0
    private let outputQueue: DispatchQueue

    init(sessionQueue: DispatchQueue) {
        self.sessionQueue = sessionQueue
        self.output = .init()
        self.outputQueue = .init(label: "com.mijick.camera.video-data", qos: .userInitiated)
        super.init()

        sessionQueue.setSpecific(key: registrationKey, value: 1)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: outputQueue)
    }
}

private final class WeakCameraFrameObserverBox: @unchecked Sendable {
    weak var observer: (any CameraFrameObserver)?

    init(observer: (any CameraFrameObserver)?) {
        self.observer = observer
    }
}

// MARK: Registration
extension CameraManagerFrameOutput {
    func setObserver(_ observer: (any CameraFrameObserver)?, queue: DispatchQueue) {
        let replace = {
            self.stateLock.lock()
            self.observerBox = .init(observer: observer)
            self.callbackQueue = observer.map { _ in
                .init(label: "com.mijick.camera.frame-callback", target: queue)
            }
            self.registrationID &+= 1
            self.stateLock.unlock()
        }

        if DispatchQueue.getSpecific(key: registrationKey) != nil {
            replace()
        } else {
            sessionQueue.sync(execute: replace)
        }
    }
}

// MARK: Output Connection
extension CameraManagerFrameOutput {
    func configureConnection(orientation: AVCaptureVideoOrientation, isMirrored: Bool) {
        sessionQueue.sync {
            guard let connection = output.connection(with: .video) else { return }
            if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = isMirrored }
        }
    }
}

// MARK: Capture
extension CameraManagerFrameOutput: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let frame = CameraFrame(
            sampleBuffer: sampleBuffer,
            videoOrientation: connection.videoOrientation,
            isMirrored: connection.isVideoMirrored
        )
        deliver(frame: frame)
        if let preview, let pixelBuffer = CameraMetalView.copyPixelBuffer(from: sampleBuffer) {
            Task { @MainActor [weak preview, pixelBuffer] in
                preview?.render(pixelBuffer: pixelBuffer)
            }
        }
    }
}

extension CameraManagerFrameOutput {
    func deliver(frame: CameraFrame) {
        let registration: (box: WeakCameraFrameObserverBox?, queue: DispatchQueue?, id: UInt) = {
            stateLock.lock()
            defer { stateLock.unlock() }
            return (observerBox, callbackQueue, registrationID)
        }()

        if let box = registration.box, let queue = registration.queue, let cameraManager {
            let registrationID = registration.id
            queue.sync { [weak self, weak cameraManager] in
                guard let self,
                      self.isCurrentRegistration(registrationID),
                      let observer = box.observer,
                      let cameraManager
                else { return }

                observer.cameraManager(cameraManager, didOutput: frame)
            }
        }
    }
}

private extension CameraManagerFrameOutput {
    func isCurrentRegistration(_ id: UInt) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return registrationID == id
    }
}
