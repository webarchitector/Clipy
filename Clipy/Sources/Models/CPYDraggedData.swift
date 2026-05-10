//
//  CPYDraggedData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/07/14.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

final class CPYDraggedData: NSObject, NSSecureCoding {

    // MARK: - Properties
    let type: DragType
    let identifier: String
    let parentIdentifier: String
    let index: Int

    // MARK: - Enums
    enum DragType: Int {
        case folder, snippet
    }

    // MARK: - Initialize
    init(type: DragType, identifier: String, parentIdentifier: String, index: Int) {
        self.type = type
        self.identifier = identifier
        self.parentIdentifier = parentIdentifier
        self.index = index
        super.init()
    }

    // MARK: - NSSecureCoding
    static var supportsSecureCoding: Bool { true }

    required init?(coder aDecoder: NSCoder) {
        self.type = DragType(rawValue: aDecoder.decodeInteger(forKey: "type")) ?? .folder
        self.identifier = (aDecoder.decodeObject(of: NSString.self, forKey: "identifier") as String?) ?? ""
        self.parentIdentifier = (aDecoder.decodeObject(of: NSString.self, forKey: "parentIdentifier") as String?) ?? ""
        self.index = aDecoder.decodeInteger(forKey: "index")
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(type.rawValue, forKey: "type")
        aCoder.encode(identifier as NSString, forKey: "identifier")
        aCoder.encode(parentIdentifier as NSString, forKey: "parentIdentifier")
        aCoder.encode(index, forKey: "index")
    }
}
