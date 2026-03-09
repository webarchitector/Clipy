//
//  NSCoding+Archive.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/19.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

enum LegacyKeyedArchive {
    static func archivedData(withRootObject rootObject: Any) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: rootObject, requiringSecureCoding: false)
    }

    static func unarchivedObject<T>(of type: T.Type, from data: Data) -> T? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            unarchiver.decodingFailurePolicy = .setErrorAndReturn
            defer { unarchiver.finishDecoding() }
            return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? T
        } catch {
            return nil
        }
    }

    static func unarchivedObject<T>(of type: T.Type, fromFile path: String) -> T? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return unarchivedObject(of: type, from: data)
    }

    @discardableResult
    static func archiveRootObject(_ rootObject: Any, toFile path: String) -> Bool {
        guard let data = archivedData(withRootObject: rootObject) else { return false }

        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

extension NSCoding {
    func archive() -> Data? {
        return LegacyKeyedArchive.archivedData(withRootObject: self)
    }
}

extension Array where Element: NSCoding {
    func archive() -> Data? {
        return LegacyKeyedArchive.archivedData(withRootObject: self)
    }
}
