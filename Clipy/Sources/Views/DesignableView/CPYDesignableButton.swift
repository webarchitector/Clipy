//
//  CPYDesignableButton.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

class CPYDesignableButton: NSButton {

    @IBInspectable var textColor: NSColor = .labelColor {
        didSet {
            updateAttributedTitle()
        }
    }
    override var title: String {
        didSet {
            updateAttributedTitle()
        }
    }

    // MARK: - Initialize
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initView()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        updateAttributedTitle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAttributedTitle()
    }

    private func initView() {
        updateAttributedTitle()
    }

    private func updateAttributedTitle() {
        let attributedString = NSAttributedString(string: title, attributes: [.foregroundColor: textColor])
        attributedTitle = attributedString
    }
}
