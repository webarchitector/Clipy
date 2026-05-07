//
//  CPYClip.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift

final class CPYClip: Object {

    // MARK: - Properties
    @objc dynamic var dataPath = ""
    @objc dynamic var title = ""
    @objc dynamic var dataHash = ""
    @objc dynamic var primaryType = ""
    @objc dynamic var updateTime = 0
    @objc dynamic var thumbnailPath = ""
    @objc dynamic var isColorCode = false
    /// User-toggled pin. Pinned clips sort to the top of the history
    /// window and survive `maxHistorySize` trimming.
    @objc dynamic var isPinned = false
    /// Bundle identifier of the app that was frontmost when this clip was
    /// captured. Empty when unknown (legacy clips, anonymous sources).
    @objc dynamic var sourceBundleID = ""

    // MARK: Primary Key
    override static func primaryKey() -> String? {
        return "dataHash"
    }

}
