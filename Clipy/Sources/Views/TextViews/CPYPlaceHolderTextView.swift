//
//  CPYPlaceHolderTextView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/06/29.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

class CPYPlaceHolderTextView: NSTextView {

    // MARK: - Properties
    @IBInspectable var placeHolderColor: NSColor = .disabledControlTextColor {
        didSet {
            needsDisplay = true
        }
    }
    @IBInspectable var placeHolderText: String = "" {
        didSet {
            needsDisplay = true
        }
    }
    override var textContainerOrigin: NSPoint {
        return NSPoint(x: 0, y: 7)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Draw
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if placeHolderText.isEmpty { return }
        if !string.isEmpty { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.baseWritingDirection = .leftToRight
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14),
                                                         .foregroundColor: placeHolderColor,
                                                         .paragraphStyle: paragraphStyle]
        placeHolderText.draw(at: NSPoint(x: 5, y: 5), withAttributes: attributes)
    }

}
