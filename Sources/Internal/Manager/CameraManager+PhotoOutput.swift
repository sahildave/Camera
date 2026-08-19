//
//  CameraManager+PhotoOutput.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

@MainActor class CameraManagerPhotoOutput: NSObject {
    private(set) var parent: CameraManager!
    private(set) var output: AVCapturePhotoOutput = .init()
    private(set) var fullQualityCaptureDeviceID: String?
}

// MARK: Setup
extension CameraManagerPhotoOutput {
    func setup(parent: CameraManager) throws(MCameraError) {
        self.parent = parent
        try self.parent.addCaptureOutput(output)
        configureFullQualityCapture(for: parent.activeVideoInputDevice)
    }

    /**
     Recomputes the full-quality capture ceiling from the given device's active format.

     Must be called for every active video input change, not only at setup: swapping
     the camera position or the rear lens activates a different format, and the
     previous format's maximum dimensions may not be supported by the new one.
     */
    func configureFullQualityCapture(for device: (any CaptureDevice)?) {
        output.maxPhotoQualityPrioritization = .quality
        fullQualityCaptureDeviceID = device?.uniqueID
        // `setMaxPhotoDimensions` raises an uncatchable ObjC exception unless the output is
        // already connected to a video source with an active format.
        if #available(iOS 16.0, *), output.connection(with: .video) != nil, let maxPhotoDimensions = getMaxPhotoDimensions(device) { output.maxPhotoDimensions = maxPhotoDimensions }
    }
}
private extension CameraManagerPhotoOutput {
    @available(iOS 16.0, *) func getMaxPhotoDimensions(_ device: (any CaptureDevice)?) -> CMVideoDimensions? {
        guard let device = device as? AVCaptureDevice else { return nil }
        return device.activeFormat.supportedMaxPhotoDimensions.max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
    }
}


// MARK: - CAPTURE PHOTO



// MARK: Capture
extension CameraManagerPhotoOutput {
    func capture() {
        parent.setPhotoCaptureError(nil)
        guard parent.getCameraInput()?.device != nil, parent.captureSession.isRunning else { return parent.setPhotoCaptureError(.photoCaptureSessionNotReady) }

        let settings = getPhotoOutputSettings()

        configureOutput()
        output.capturePhoto(with: settings, delegate: self)
        parent.cameraMetalView.performImageCaptureAnimation()
    }
}
extension CameraManagerPhotoOutput {
    func getPhotoOutputSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = parent.attributes.flashMode.toDeviceFlashMode()
        settings.photoQualityPrioritization = output.maxPhotoQualityPrioritization
        if #available(iOS 16.0, *) { settings.maxPhotoDimensions = output.maxPhotoDimensions }
        return settings
    }
}
private extension CameraManagerPhotoOutput {
    func configureOutput() {
        guard let connection = output.connection(with: .video), connection.isVideoMirroringSupported else { return }

        connection.isVideoMirrored = parent.attributes.mirrorOutput ? parent.attributes.cameraPosition != .front : parent.attributes.cameraPosition == .front
        connection.videoOrientation = parent.attributes.deviceOrientation
    }
}

// MARK: Receive Data
extension CameraManagerPhotoOutput: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        processCapturedPhoto(imageData: photo.fileDataRepresentation(), error: error)
    }
}

// MARK: Process Captured Photo
extension CameraManagerPhotoOutput {
    func processCapturedPhoto(imageData: Data?, error: (any Error)?) {
        guard let parent else { return }
        guard error == nil else { return parent.setPhotoCaptureError(.photoCaptureFailed) }
        guard let imageData, let ciImage = CIImage(data: imageData) else { return parent.setPhotoCaptureError(.photoPostProcessingFailed) }

        let capturedCIImage = prepareCIImage(ciImage, parent.attributes.cameraFilters)
        let capturedCGImage = prepareCGImage(capturedCIImage)
        let capturedUIImage = prepareUIImage(capturedCGImage)
        guard let capturedMedia = MCameraMedia(data: capturedUIImage, originalPhotoData: imageData) else { return parent.setPhotoCaptureError(.photoPostProcessingFailed) }

        parent.setCapturedMedia(capturedMedia)
    }
}
private extension CameraManagerPhotoOutput {
    func prepareCIImage(_ ciImage: CIImage, _ filters: [CIFilter]) -> CIImage {
        ciImage.applyingFilters(filters)
    }
    func prepareCGImage(_ ciImage: CIImage) -> CGImage? {
        CIContext().createCGImage(ciImage, from: ciImage.extent)
    }
    func prepareUIImage(_ cgImage: CGImage?) -> UIImage? {
        guard let cgImage else { return nil }

        let frameOrientation = getFixedFrameOrientation()
        let orientation = UIImage.Orientation(frameOrientation)
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        return uiImage
    }
}
private extension CameraManagerPhotoOutput {
    func getFixedFrameOrientation() -> CGImagePropertyOrientation {
        guard UIDevice.current.orientation != parent.attributes.deviceOrientation.toDeviceOrientation() else { return parent.attributes.frameOrientation }

        return switch (parent.attributes.deviceOrientation, parent.attributes.cameraPosition) {
            case (.portrait, .front): .left
            case (.portrait, .back): .right
            case (.landscapeLeft, .back): .down
            case (.landscapeRight, .back): .up
            case (.landscapeLeft, .front) where parent.attributes.mirrorOutput: .up
            case (.landscapeLeft, .front): .upMirrored
            case (.landscapeRight, .front) where parent.attributes.mirrorOutput: .down
            case (.landscapeRight, .front): .downMirrored
            default: .right
        }
    }
}
