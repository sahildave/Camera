//
//  Public+Model+MCameraError.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import Foundation

public enum MCameraError: Error, Equatable, Sendable {
    case microphonePermissionsNotGranted, cameraPermissionsNotGranted
    case cannotSetupInput, cannotSetupOutput, cannotSetupMetalDevice
    case unsupportedRearLens(CameraRearLens)
    case photoCaptureSessionNotReady, photoCaptureFailed, photoPostProcessingFailed
}
