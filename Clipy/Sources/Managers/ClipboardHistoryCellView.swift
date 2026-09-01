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

    // Relative-time formatters used by the timestamp label. Created once
    // per process; both are thread-safe.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.formattingContext = .standalone
        return formatter
    }()
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private let thumbnailView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        return imageView
    }()
    /// Tiny app-icon strip on the very left of each row indicating which
    /// app produced the clip. 16×16 to match macOS menu-icon conventions.
    private let sourceIconView: NSImageView = {
        let view = NSImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }()
    /// SF Symbol pin badge, shown next to the timestamp when the clip is
    /// pinned. Filled vs empty is handled at configure time.
    private let pinView: NSImageView = {
        let view = NSImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .systemYellow
        view.image = NSImage(systemSymbolName: "pin.fill",
                             accessibilityDescription: "Pinned")
        return view
    }()
    private let titleField = NSTextField(labelWithString: "")
    private let timeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        // Weak hugging horizontal so it gives space to the title when room
        // is tight, but stays at its natural size most of the time.
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    private var titleLeadingWithImage: NSLayoutConstraint?
    private var titleLeadingWithoutImage: NSLayoutConstraint?
    private var thumbnailWidthConstraint: NSLayoutConstraint?
    private var thumbnailHeightConstraint: NSLayoutConstraint?
    // Bumped on every configure() / prepareForReuse() so an in-flight async
    // thumbnail load from a *previous* configure can't re-show an image after
    // the user toggled Show Image / Show color preview off.
    private var configureToken: UInt64 = 0

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let emphasized = backgroundStyle == .emphasized
            titleField.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
            // Lighter shade of the same role so the timestamp stays
            // legible-but-secondary in both regular and selected rows.
            timeLabel.textColor = emphasized ? .alternateSelectedControlTextColor.withAlphaComponent(0.75)
                                             : .secondaryLabelColor
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

        addSubview(sourceIconView)
        addSubview(thumbnailView)
        addSubview(titleField)
        addSubview(pinView)
        addSubview(timeLabel)

        // Two distinct title-leading constraints: when a thumbnail is shown
        // we anchor past the thumbnail; when it's hidden we anchor to the
        // source icon directly so the title gets the freed-up width instead
        // of leaving a wide blank gap.
        let withImage = titleField.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 8)
        let withoutImage = titleField.leadingAnchor.constraint(equalTo: sourceIconView.trailingAnchor, constant: 8)
        titleLeadingWithImage = withImage
        titleLeadingWithoutImage = withoutImage

        let widthC = thumbnailView.widthAnchor.constraint(equalToConstant: 40)
        let heightC = thumbnailView.heightAnchor.constraint(equalToConstant: 40)
        thumbnailWidthConstraint = widthC
        thumbnailHeightConstraint = heightC

        NSLayoutConstraint.activate([
            // 16×16 source-app badge at the very left, vertically centered.
            sourceIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sourceIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 16),
            sourceIconView.heightAnchor.constraint(equalToConstant: 16),

            thumbnailView.leadingAnchor.constraint(equalTo: sourceIconView.trailingAnchor, constant: 8),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthC,
            heightC,
            withoutImage,
            // Title fills horizontally up to the timestamp; timestamp sits
            // flush to the right edge of the row.
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: pinView.leadingAnchor, constant: -6),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Pin badge sits between the title and the timestamp. Hidden
            // for unpinned rows; the constraint keeps width fixed either
            // way so the layout doesn't shift on toggle.
            pinView.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -4),
            pinView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 12),
            pinView.heightAnchor.constraint(equalToConstant: 12),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Hard cap so a long timestamp can't push the title to nothing.
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 96)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with entry: ClipboardHistoryEntry, settings: MenuSettings) {
        configureToken &+= 1
        let token = configureToken

        // Inline thumbnail is fixed at 40×40 — `settings.thumbnailWidth/Height`
        // are PIXEL sizes for menu-popup previews (default 192) and feeding
        // them as point sizes here squeezes the title to a few characters.
        thumbnailWidthConstraint?.constant = 40
        thumbnailHeightConstraint?.constant = 40

        titleField.stringValue = entry.displayTitle
        titleField.toolTip = settings.isShowToolTip
            ? String(entry.toolTip.prefix(settings.maxLengthOfToolTip))
            : nil

        timeLabel.stringValue = ClipboardHistoryCellView.formatTimestamp(entry.updateTime)

        // Source-app icon: small badge on the very left. Empty bundle ID
        // (legacy clips, anonymous sources) hides the slot but keeps the
        // 16-pt offset so all rows share an identical title indent.
        sourceIconView.image = ClipboardHistoryCellView.iconForBundleID(entry.sourceBundleID)
        sourceIconView.toolTip = entry.sourceBundleID.isEmpty ? nil : entry.sourceBundleID

        pinView.isHidden = !entry.isPinned

        // Also suppress color thumbnails stored by older app versions.
        let wantsThumbnail = !entry.isColorCode && !entry.thumbnailPath.isEmpty && settings.isShowImage

        if wantsThumbnail {
            let titleIsPlaceholder = MenuManager.clipTypePlaceholders.contains(entry.displayTitle)
            ThumbnailCache.shared.object(forKeyAsync: entry.thumbnailPath) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, self.configureToken == token, let image = image else { return }
                    self.showThumbnail(image, hideTitle: titleIsPlaceholder)
                }
            }
        } else if settings.isShowIcon, let filePath = ClipboardHistoryCellView.firstFilePath(from: entry) {
            let icon = NSWorkspace.shared.icon(forFile: filePath)
            icon.size = NSSize(width: 32, height: 32)
            showThumbnail(icon, hideTitle: false)
        } else {
            hideThumbnail()
        }
    }

    private func showThumbnail(_ image: NSImage, hideTitle: Bool = false) {
        thumbnailView.image = image
        thumbnailView.isHidden = false
        titleLeadingWithoutImage?.isActive = false
        titleLeadingWithImage?.isActive = true
        if hideTitle {
            titleField.stringValue = ""
        }
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

    /// Compact timestamp for the right edge of each row. Recent clips read
    /// as "5m"/"2h"/"yesterday"; anything older than a week falls back to a
    /// short absolute date so the eye doesn't have to translate "8 weeks ago".
    private static func formatTimestamp(_ unixTime: Int) -> String {
        guard unixTime > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(unixTime))
        let secondsAgo = Date().timeIntervalSince(date)
        if secondsAgo < 7 * 86400 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return absoluteFormatter.string(from: date)
    }

    /// Resolve a bundle identifier to the running / installed app's icon.
    /// Cached per bundle so we don't hit Launch Services on every redraw.
    /// Returns nil for unknown / empty bundle IDs so callers can hide
    /// the slot.
    private static let bundleIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    static func iconForBundleID(_ bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = bundleIconCache.object(forKey: key) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        bundleIconCache.setObject(icon, forKey: key)
        return icon
    }

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
        configureToken &+= 1
        hideThumbnail()
    }
}
