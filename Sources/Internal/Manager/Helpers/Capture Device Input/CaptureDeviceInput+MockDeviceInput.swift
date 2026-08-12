//
//  CaptureDeviceInput+MockDeviceInput.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

class MockDeviceInput: NSObject, CaptureDeviceInput, @unchecked Sendable { required override init() {}
    var device: MockCaptureDevice = .init()

    nonisolated(unsafe) static var supportedRearDeviceTypes: Set<AVCaptureDevice.DeviceType> = [
        .builtInUltraWideCamera,
        .builtInWideAngleCamera,
        .builtInTelephotoCamera
    ]
}

// MARK: Methods
extension MockDeviceInput {
    static func get(mediaType: AVMediaType, position: AVCaptureDevice.Position?) -> Self? { .init() }

    static func get(mediaType: AVMediaType, deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position?) -> Self? {
        guard mediaType == .video,
              position == .back,
              supportedRearDeviceTypes.contains(deviceType)
        else { return nil }

        let input = Self.init()
        input.device.deviceType = deviceType
        return input
    }
}

// MARK: Equatable
extension MockDeviceInput {
    static func == (lhs: MockDeviceInput, rhs: MockDeviceInput) -> Bool { lhs.device.uniqueID == rhs.device.uniqueID }
}
