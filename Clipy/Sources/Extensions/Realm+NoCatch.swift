//
//  Realm+NoCatch.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/11.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import os
import RealmSwift

private let realmLog = Logger(subsystem: "com.clipy-app.Clipy", category: "realm")

extension Realm {
    static func safeInstance() -> Realm? {
        do {
            return try Realm()
        } catch {
            realmLog.error("Realm initialization failed: \(error.localizedDescription, privacy: .public)")
            // In dev/test builds, halt so a broken migration or schema
            // doesn't get masked behind silent nil-returns; in Release the
            // app stays running so the user can at least see something
            // (NSLog/Console-visible) rather than crash on every launch.
            assertionFailure("Realm init failed: \(error)")
            return nil
        }
    }

    func transaction(_ block: (() throws -> Void)) {
        do {
            try write(block)
        } catch {
            realmLog.error("Realm transaction error: \(error.localizedDescription, privacy: .public)")
            assertionFailure("Realm transaction failed: \(error)")
        }
    }
}
