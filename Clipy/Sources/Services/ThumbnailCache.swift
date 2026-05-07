//
//  ThumbnailCache.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//

import AppKit
import Foundation

// Thread-safe by construction: NSCache is internally lock-free, all
// disk IO is funneled through `writeQueue`/`readQueue`, and other
// fields are immutable after init. @unchecked Sendable keeps the
// queue-based design intact under Swift 6 strict concurrency without
// rewriting the cache as an actor.
final class ThumbnailCache: @unchecked Sendable {

    static let shared = ThumbnailCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let writeQueue = DispatchQueue(label: "com.clipy-app.Clipy.ThumbnailCache.write", qos: .utility)
    private let readQueue = DispatchQueue(label: "com.clipy-app.Clipy.ThumbnailCache.read", qos: .userInitiated, attributes: .concurrent)
    private let directory: String

    init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 10 * 1024 * 1024

        let cachesBase: String
        if let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cachesBase = url.path
        } else {
            cachesBase = NSTemporaryDirectory()
        }
        let bundleID = Bundle.main.bundleIdentifier ?? Constants.Application.name
        directory = (cachesBase as NSString)
            .appendingPathComponent(bundleID)
            + "/thumbnails"
        _ = CPYUtilities.prepareSaveToPath(directory)
    }

    func setObjectAsync(_ image: NSImage, forKey key: String) {
        let nsKey = key as NSString
        memoryCache.setObject(image, forKey: nsKey, cost: estimatedCost(of: image))
        let path = self.path(for: key)
        writeQueue.async {
            // Skip the TIFF intermediate: encoding image → TIFF → NSBitmapImageRep → PNG
            // costs three full-size buffers. CGImage → NSBitmapImageRep → PNG is two.
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func object(forKeyAsync key: String, completion: @escaping (NSImage?) -> Void) {
        let nsKey = key as NSString
        if let cached = memoryCache.object(forKey: nsKey) {
            completion(cached)
            return
        }
        let path = self.path(for: key)
        readQueue.async { [weak self] in
            let image = NSImage(contentsOfFile: path)
            if let image = image, let self = self {
                self.memoryCache.setObject(image, forKey: nsKey, cost: self.estimatedCost(of: image))
            }
            completion(image)
        }
    }

    func removeObject(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        let path = self.path(for: key)
        writeQueue.async {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func path(for key: String) -> String {
        return (directory as NSString).appendingPathComponent(key)
    }

    private func estimatedCost(of image: NSImage) -> Int {
        let size = image.size
        return Int(size.width * size.height * 4)
    }
}
