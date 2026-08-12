//
//  Public+Model+CameraFrame.swift of MijickCamera
//

@preconcurrency import AVFoundation

/**
 A live video frame delivered by the camera's existing video-data output.

 The library owns `sampleBuffer`. It is valid only for the duration of the
 observer callback. An asynchronous consumer must copy the data it needs before
 returning from that callback.
 */
public struct CameraFrame: @unchecked Sendable {
    public let sampleBuffer: CMSampleBuffer
    public let videoOrientation: AVCaptureVideoOrientation
    public let isMirrored: Bool

    public init(
        sampleBuffer: CMSampleBuffer,
        videoOrientation: AVCaptureVideoOrientation,
        isMirrored: Bool
    ) {
        self.sampleBuffer = sampleBuffer
        self.videoOrientation = videoOrientation
        self.isMirrored = isMirrored
    }
}

/**
 Receives live frames without taking ownership of their sample buffers.

 Implementations are called serially on the queue supplied to
 ``CameraManager/setFrameObserver(_:queue:)`` while the capture delivery is
 still active. Keep the callback bounded and copy data needed for asynchronous
 work before returning.
 */
public protocol CameraFrameObserver: AnyObject {
    func cameraManager(_ cameraManager: CameraManager, didOutput frame: CameraFrame)
}
