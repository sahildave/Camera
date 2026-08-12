//
//  Tests+ForkFrameLensHooks.swift of MijickCamera
//

import Testing
import AVFoundation
import Foundation
@testable import MijickCamera

@MainActor @Suite("Fork Frame and Lens Hooks", .serialized) struct ForkFrameLensHooksTests {
    @Test("Selecting a rear lens swaps the exact physical input and completes once")
    func selectingRearLensSwapsExactInput() async throws {
        let session = MockCaptureSession()
        let cameraManager = CameraManager(
            captureSession: session,
            captureDeviceInputType: MockDeviceInput.self
        )
        try session.add(input: cameraManager.backCameraInput)

        let completionCount = CompletionCount()
        let result = await withCheckedContinuation { continuation in
            cameraManager.selectRearLens(.telephoto) { result in
                completionCount.increment()
                continuation.resume(returning: result)
            }
        }

        #expect(result == .success(.telephoto))
        #expect(completionCount.value == 1)
        #expect(session.deviceInputs.count == 1)
        #expect(session.deviceInputs.first?.device.deviceType == .builtInTelephotoCamera)
        #expect(cameraManager.backCameraInput?.device.deviceType == .builtInTelephotoCamera)
    }

    @Test("Unsupported rear lenses fail without substituting a different input")
    func unsupportedRearLensFailsWithoutSubstitution() async throws {
        let previousSupportedDeviceTypes = MockDeviceInput.supportedRearDeviceTypes
        defer { MockDeviceInput.supportedRearDeviceTypes = previousSupportedDeviceTypes }
        MockDeviceInput.supportedRearDeviceTypes = [.builtInWideAngleCamera]

        let session = MockCaptureSession()
        let cameraManager = CameraManager(
            captureSession: session,
            captureDeviceInputType: MockDeviceInput.self
        )
        try session.add(input: cameraManager.backCameraInput)

        let result = await withCheckedContinuation { continuation in
            cameraManager.selectRearLens(.telephoto) { result in
                continuation.resume(returning: result)
            }
        }

        #expect(result == .failure(.unsupportedRearLens(.telephoto)))
        #expect(session.deviceInputs.count == 1)
        #expect(session.deviceInputs.first?.device.deviceType == .builtInWideAngleCamera)
    }

    @Test("Frame observation uses the supplied serial queue and replaces weak observers")
    func frameObservationQueueAndWeakReplacement() throws {
        let cameraManager = CameraManager(
            captureSession: MockCaptureSession(),
            captureDeviceInputType: MockDeviceInput.self
        )
        cameraManager.frameOutput.cameraManager = cameraManager

        let callbackQueue = DispatchQueue(label: "duocam.frame-test")
        let queueKey = DispatchSpecificKey<String>()
        callbackQueue.setSpecific(key: queueKey, value: "frame-test")
        let probe = FrameProbe()
        let previousProbe = FrameProbe()

        let retainedFirstObserver = TestFrameObserver { frame in
            previousProbe.record(frame, on: DispatchQueue.getSpecific(key: queueKey))
        }
        cameraManager.setFrameObserver(retainedFirstObserver, queue: callbackQueue)

        weak var firstObserver: TestFrameObserver?
        do {
            let observer = TestFrameObserver { frame in
                probe.record(frame, on: DispatchQueue.getSpecific(key: queueKey))
            }
            firstObserver = observer
            cameraManager.setFrameObserver(observer, queue: callbackQueue)
        }
        #expect(firstObserver == nil)

        let secondObserver = TestFrameObserver { frame in
            probe.record(frame, on: DispatchQueue.getSpecific(key: queueKey))
        }
        cameraManager.setFrameObserver(secondObserver, queue: callbackQueue)

        let frame = CameraFrame(
            sampleBuffer: try makeSampleBuffer(),
            videoOrientation: .landscapeRight,
            isMirrored: true
        )
        cameraManager.frameOutput.deliver(frame: frame)

        #expect(probe.waitForFrame())
        #expect(probe.orientation == .landscapeRight)
        #expect(probe.isMirrored == true)
        #expect(probe.bufferWasValid)
        #expect(probe.queueValue == "frame-test")
        #expect(probe.deliveryCount == 1)
        #expect(previousProbe.deliveryCount == 0)
    }
}

private final class TestFrameObserver: CameraFrameObserver {
    let handler: @Sendable (CameraFrame) -> Void

    init(handler: @escaping @Sendable (CameraFrame) -> Void) {
        self.handler = handler
    }

    func cameraManager(_ cameraManager: CameraManager, didOutput frame: CameraFrame) {
        handler(frame)
    }
}

private final class FrameProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private(set) var orientation: AVCaptureVideoOrientation?
    private(set) var isMirrored = false
    private(set) var bufferWasValid = false
    private(set) var queueValue: String?
    private(set) var deliveryCount = 0

    func record(_ frame: CameraFrame, on queueValue: String?) {
        lock.lock()
        orientation = frame.videoOrientation
        isMirrored = frame.isMirrored
        bufferWasValid = CMSampleBufferIsValid(frame.sampleBuffer)
        self.queueValue = queueValue
        deliveryCount += 1
        lock.unlock()
        semaphore.signal()
    }

    func waitForFrame() -> Bool {
        semaphore.wait(timeout: .now() + 2) == .success
    }
}

private func makeSampleBuffer() throws -> CMSampleBuffer {
    var blockBuffer: CMBlockBuffer?
    var sampleBuffer: CMSampleBuffer?
    CMBlockBufferCreateEmpty(
        allocator: kCFAllocatorDefault,
        capacity: 0,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    let status = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: nil,
        sampleCount: 0,
        sampleTimingEntryCount: 0,
        sampleTimingArray: nil,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else {
        throw NSError(domain: "DuoCamTests", code: Int(status))
    }
    return sampleBuffer
}

private final class CompletionCount: @unchecked Sendable {
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
