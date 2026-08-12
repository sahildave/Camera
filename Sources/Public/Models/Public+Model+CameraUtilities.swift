//
//  Public+Model+CameraUtilities.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import AVKit

// MARK: Camera Output Type
public enum CameraOutputType: CaseIterable {
    case photo
    case video
}

// MARK: Camera Position
public enum CameraPosition: CaseIterable {
    case back
    case front
}

// MARK: Rear Camera Lens
public enum CameraRearLens: CaseIterable, Equatable, Sendable {
    case ultraWide
    case wide
    case telephoto

    public var deviceType: AVCaptureDevice.DeviceType { switch self {
        case .ultraWide: .builtInUltraWideCamera
        case .wide: .builtInWideAngleCamera
        case .telephoto: .builtInTelephotoCamera
    }}
}

// MARK: Camera Flash Mode
public enum CameraFlashMode: CaseIterable {
    case off
    case on
    case auto
}

// MARK: Camera Light Mode
public enum CameraLightMode: CaseIterable {
    case off
    case on
}

// MARK: Camera HDR Mode
public enum CameraHDRMode: CaseIterable {
    case off
    case on
    case auto
}
