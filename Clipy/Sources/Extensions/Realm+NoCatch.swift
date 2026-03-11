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
import RealmSwift

extension Realm {
    static func safeInstance() -> Realm? {
        do {
            return try Realm()
        } catch {
            NSLog("Realm initialization failed: %@", "\(error)")
            return nil
        }
    }

    func transaction(_ block: (() throws -> Void)) {
        do {
            try write(block)
        } catch {
            NSLog("Realm transaction error: %@", "\(error)")
        }
    }
}
