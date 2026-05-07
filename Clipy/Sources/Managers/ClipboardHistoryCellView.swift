//
//  ClipboardHistoryCellView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class ClipboardHistoryCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipboardHistoryCellView")

    private let thumbnailView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        return imageView
    }()
    private let titleField = NSTextField(labelWithString: "")
    private var titleLeadingWithImage: NSLayoutConstraint?
    private var titleLeadingWithoutImage: NSLayoutConstraint?

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            titleField.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = ClipboardHistoryCellView.reuseIdentifier

        wantsLayer = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.font = NSFont.systemFont(ofSize: 13)
        titleField.textColor = .labelColor

        addSubview(thumbnailView)
        addSubview(titleField)

        let withImage = titleField.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 8)
        let withoutImage = titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        titleLeadingWithImage = withImage
        titleLeadingWithoutImage = withoutImage

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailView.heightAnchor.constraint(equalToConstant: 64),
            withoutImage,
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with entry: ClipboardHistoryEntry, settings: MenuSettings) {
        titleField.stringValue = entry.displayTitle
        titleField.toolTip = settings.isShowToolTip
            ? String(entry.toolTip.prefix(settings.maxLengthOfToolTip))
            : nil

        let wantsThumbnail = !entry.thumbnailPath.isEmpty &&
            ((!entry.isColorCode && settings.isShowImage) || (entry.isColorCode && settings.isShowColorCode))

        if wantsThumbnail {
            ThumbnailCache.shared.object(forKeyAsync: entry.thumbnailPath) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, let image = image else { return }
                    self.showThumbnail(image)
                }
            }
        } else if settings.isShowIcon, let filePath = ClipboardHistoryCellView.firstFilePath(from: entry) {
            let icon = NSWorkspace.shared.icon(forFile: filePath)
            icon.size = NSSize(width: 32, height: 32)
            showThumbnail(icon)
        } else {
            hideThumbnail()
        }
    }

    private func showThumbnail(_ image: NSImage) {
        thumbnailView.image = image
        thumbnailView.isHidden = false
        titleLeadingWithoutImage?.isActive = false
        titleLeadingWithImage?.isActive = true
    }

    private func hideThumbnail() {
        thumbnailView.image = nil
        thumbnailView.isHidden = true
        titleLeadingWithImage?.isActive = false
        titleLeadingWithoutImage?.isActive = true
    }

    private static let filePathCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 200
        return cache
    }()

    static func firstFilePath(from entry: ClipboardHistoryEntry) -> String? {
        let ptype = NSPasteboard.PasteboardType(rawValue: entry.primaryType)
        guard ptype == .deprecatedFilenames || ptype == .fileURL else { return nil }
        let cacheKey = entry.dataPath as NSString
        if let cached = filePathCache.object(forKey: cacheKey) {
            return cached as String
        }
        let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: entry.dataPath)
        if let fileCachePath = clipData?.fileNames.first {
            filePathCache.setObject(fileCachePath as NSString, forKey: cacheKey)
            return fileCachePath
        }
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hideThumbnail()
    }
}
