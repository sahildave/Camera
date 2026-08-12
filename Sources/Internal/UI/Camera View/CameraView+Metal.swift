//
//  CameraView+Metal.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import MetalKit
import AVKit

@MainActor class CameraMetalView: MTKView {
    private(set) var parent: CameraManager!
    private(set) var ciContext: CIContext!
    private(set) var commandQueue: MTLCommandQueue!
    private(set) var currentFrame: CIImage?
    private(set) var focusIndicator: CameraFocusIndicatorView = .init()
    private(set) var isAnimating: Bool = false
    private let previewProcessingQueue = DispatchQueue(label: "com.mijick.camera.preview-processing", qos: .userInitiated)
    private let previewProcessor = CameraPreviewProcessor()
}

// MARK: Setup
extension CameraMetalView {
    func setup(parent: CameraManager) throws(MCameraError) {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else { throw .cannotSetupMetalDevice }

        self.assignInitialValues(parent: parent, metalDevice: metalDevice)
        self.configureMetalView(metalDevice: metalDevice)
        self.addToParent(parent.cameraView)
    }
}

final class CameraPreviewPixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer

    init(value: CVPixelBuffer) {
        self.value = value
    }
}

extension CameraMetalView {
    nonisolated static func copyPixelBuffer(from sampleBuffer: CMSampleBuffer) -> CameraPreviewPixelBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let copy = copyPixelBuffer(source)
        else { return nil }

        return .init(value: copy)
    }
}

private extension CameraMetalView {
    nonisolated static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        var destination: CVPixelBuffer?

        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &destination
        ) == kCVReturnSuccess,
        let destination
        else { return nil }

        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane)
                else { return nil }

                copyRows(
                    from: sourceBase,
                    to: destinationBase,
                    sourceBytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(source, plane),
                    destinationBytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(destination, plane),
                    rowCount: CVPixelBufferGetHeightOfPlane(source, plane)
                )
            }
        } else {
            guard let sourceBase = CVPixelBufferGetBaseAddress(source),
                  let destinationBase = CVPixelBufferGetBaseAddress(destination)
            else { return nil }

            copyRows(
                from: sourceBase,
                to: destinationBase,
                sourceBytesPerRow: CVPixelBufferGetBytesPerRow(source),
                destinationBytesPerRow: CVPixelBufferGetBytesPerRow(destination),
                rowCount: CVPixelBufferGetHeight(source)
            )
        }

        CVBufferPropagateAttachments(source, destination)
        return destination
    }

    nonisolated static func copyRows(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        sourceBytesPerRow: Int,
        destinationBytesPerRow: Int,
        rowCount: Int
    ) {
        let bytesPerRow = min(sourceBytesPerRow, destinationBytesPerRow)
        for row in 0..<rowCount {
            let sourceRow = source.advanced(by: row * sourceBytesPerRow)
            let destinationRow = destination.advanced(by: row * destinationBytesPerRow)
            destinationRow.copyMemory(from: sourceRow, byteCount: bytesPerRow)
        }
    }
}

private extension CameraMetalView {
    func assignInitialValues(parent: CameraManager, metalDevice: MTLDevice) {
        self.parent = parent
        self.ciContext = CIContext(mtlDevice: metalDevice)
        self.commandQueue = metalDevice.makeCommandQueue()
    }
    func configureMetalView(metalDevice: MTLDevice) {
        self.parent.cameraView.alpha = 0

        self.delegate = self
        self.device = metalDevice
        self.isPaused = true
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = false
        self.autoResizeDrawable = false
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
    }
}


// MARK: - ANIMATIONS



// MARK: Camera Entrance
extension CameraMetalView {
    func performCameraEntranceAnimation() { UIView.animate(withDuration: 0.33) { [self] in
        parent.cameraView.alpha = 1
    }}
}

// MARK: Image Capture
extension CameraMetalView {
    func performImageCaptureAnimation() {
        let blackMatte = createBlackMatte()

        parent.cameraView.addSubview(blackMatte)
        animateBlackMatte(blackMatte)
    }
}
private extension CameraMetalView {
    func createBlackMatte() -> UIView {
        let view = UIView()
        view.frame = parent.cameraView.frame
        view.backgroundColor = .init(resource: .mijickBackgroundPrimary)
        view.alpha = 0
        return view
    }
    func animateBlackMatte(_ view: UIView) {
        UIView.animate(withDuration: 0.16, animations: { view.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.16, animations: { view.alpha = 0 }) { _ in
                view.removeFromSuperview()
            }
        }
    }
}

// MARK: Camera Flip
extension CameraMetalView {
    func beginCameraFlipAnimation() async {
        let snapshot = createSnapshot()
        isAnimating = true
        insertBlurView(snapshot)
        animateBlurFlip()

        await Task.sleep(seconds: 0.01)
    }
    func finishCameraFlipAnimation() async {
        guard let blurView = parent.cameraView.viewWithTag(.blurViewTag) else { return }

        await Task.sleep(seconds: 0.44)
        UIView.animate(withDuration: 0.3, animations: { blurView.alpha = 0 }) { [self] _ in
            blurView.removeFromSuperview()
            isAnimating = false
        }
    }
}
private extension CameraMetalView {
    func createSnapshot() -> UIImage? {
        guard let currentFrame else { return nil }

        let image = UIImage(ciImage: currentFrame)
        return image
    }
    func insertBlurView(_ snapshot: UIImage?) {
        let blurView = UIImageView(frame: parent.cameraView.frame)
        blurView.image = snapshot
        blurView.contentMode = .scaleAspectFill
        blurView.clipsToBounds = true
        blurView.tag = .blurViewTag
        blurView.applyBlurEffect(style: .regular)

        parent.cameraView.addSubview(blurView)
    }
    func animateBlurFlip() {
        UIView.transition(with: parent.cameraView, duration: 0.44, options: cameraFlipAnimationTransition) {}
    }
}
private extension CameraMetalView {
    var cameraFlipAnimationTransition: UIView.AnimationOptions { parent.attributes.cameraPosition == .back ? .transitionFlipFromLeft : .transitionFlipFromRight }
}

// MARK: Camera Focus
extension CameraMetalView {
    func performCameraFocusAnimation(touchPoint: CGPoint) {
        removeExistingFocusIndicatorAnimations()

        let focusIndicator = focusIndicator.create(at: touchPoint)
        parent.cameraView.addSubview(focusIndicator)
        animateFocusIndicator(focusIndicator)
    }
}
private extension CameraMetalView {
    func removeExistingFocusIndicatorAnimations() { if let view = parent.cameraView.viewWithTag(.focusIndicatorTag) {
        view.removeFromSuperview()
    }}
    func animateFocusIndicator(_ focusIndicator: UIImageView) {
        UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, animations: { focusIndicator.transform = .init(scaleX: 1, y: 1) }) { _ in
            UIView.animate(withDuration: 0.44, delay: 1.44, animations: { focusIndicator.alpha = 0.2 }) { _ in
                UIView.animate(withDuration: 0.44, delay: 1.44, animations: { focusIndicator.alpha = 0 })
            }
        }
    }
}

// MARK: Camera Orientation
extension CameraMetalView {
    func beginCameraOrientationAnimation(if shouldAnimate: Bool) async { if shouldAnimate {
        parent.cameraView.alpha = 0
        await Task.sleep(seconds: 0.1)
    }}
    func finishCameraOrientationAnimation(if shouldAnimate: Bool) { if shouldAnimate {
        UIView.animate(withDuration: 0.2, delay: 0.1) { self.parent.cameraView.alpha = 1 }
    }}
}


// MARK: - CAPTURING FRAMES



extension CameraMetalView {
    func render(pixelBuffer: CameraPreviewPixelBuffer) {
        let configuration = CameraPreviewConfiguration(
            frameOrientation: parent.attributes.frameOrientation,
            filters: parent.attributes.cameraFilters
        )
        let previewProcessingQueue = self.previewProcessingQueue
        let previewProcessor = self.previewProcessor

        previewProcessingQueue.async { [weak self, pixelBuffer, configuration, previewProcessor] in
            guard let image = previewProcessor.process(pixelBuffer: pixelBuffer.value, configuration: configuration) else { return }
            let processedFrame = ProcessedCameraFrame(image: image)
            Task { @MainActor [weak self, processedFrame] in
                self?.redrawCameraView(processedFrame.image)
            }
        }
    }
}
private extension CameraMetalView {
    func redrawCameraView(_ frame: CIImage) {
        currentFrame = frame
        draw()
    }
}

private struct CameraPreviewConfiguration: @unchecked Sendable {
    let frameOrientation: CGImagePropertyOrientation
    let filters: [CIFilter]
}

private final class ProcessedCameraFrame: @unchecked Sendable {
    let image: CIImage

    init(image: CIImage) {
        self.image = image
    }
}

private final class CameraPreviewProcessor: @unchecked Sendable {
    func process(pixelBuffer: CVPixelBuffer, configuration: CameraPreviewConfiguration) -> CIImage? {
        let currentFrame = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(configuration.frameOrientation)
        return currentFrame.applyingFilters(configuration.filters)
    }
}

// MARK: Draw
extension CameraMetalView: MTKViewDelegate {
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciImage = currentFrame,
              let currentDrawable = view.currentDrawable
        else { return }

        changeDrawableSize(view, ciImage)
        renderView(view, currentDrawable, commandBuffer, ciImage)
        commitBuffer(currentDrawable, commandBuffer)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
private extension CameraMetalView {
    func changeDrawableSize(_ view: MTKView, _ ciImage: CIImage) {
        view.drawableSize = ciImage.extent.size
    }
    func renderView(_ view: MTKView, _ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer, _ ciImage: CIImage) { ciContext.render(
        ciImage,
        to: currentDrawable.texture,
        commandBuffer: commandBuffer,
        bounds: .init(origin: .zero, size: view.drawableSize),
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )}
    func commitBuffer(_ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer) {
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
