//
//  NSImage+Resize.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/07/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa

extension NSImage {
    func resizeImage(_ width: CGFloat, _ height: CGFloat) -> NSImage? {
        guard let tiffData = self.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let origWidth = CGFloat(cgImage.width)
        let origHeight = CGFloat(cgImage.height)
        guard origWidth > 0, origHeight > 0 else { return nil }

        let aspect = origWidth / origHeight

        var newWidth: CGFloat
        var newHeight: CGFloat

        if aspect >= 1 {
            newWidth = width
            newHeight = newWidth / aspect
            if height < newHeight {
                newHeight = height
                newWidth = height * aspect
            }
        } else {
            newHeight = height
            newWidth = height * aspect
            if width < newWidth {
                newWidth = width
                newHeight = width / aspect
            }
        }

        newWidth = min(newWidth, origWidth)
        newHeight = min(newHeight, origHeight)

        let intWidth = Int(newWidth.rounded())
        let intHeight = Int(newHeight.rounded())
        guard intWidth > 0, intHeight > 0 else { return nil }

        guard let context = CGContext(data: nil,
                                      width: intWidth,
                                      height: intHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: intWidth, height: intHeight))

        guard let resizedCG = context.makeImage() else { return nil }
        return NSImage(cgImage: resizedCG, size: NSSize(width: intWidth, height: intHeight))
    }
}
