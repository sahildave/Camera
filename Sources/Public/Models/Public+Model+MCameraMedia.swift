//
//  Public+Model+MCameraMedia.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI

// MARK: Getters
public extension MCameraMedia {
    /**
     Gets the image from the media object.
     */
    func getImage() -> UIImage? { image }

    /**
     Gets the video URL from the media object.
     */
    func getVideo() -> URL? { video }

    /**
     Gets the unmodified file data of the captured photo, preserving its container, EXIF metadata and any auxiliary depth or matte data.

     - note: Available for photos only. ``getImage()`` returns the decoded and filtered image of the same capture, so the consumer chooses which one it needs.
     */
    func getOriginalPhotoData() -> Data? { originalPhotoData }
}
