//
//  HistoryPreviewView.swift
//
//  Right-side pane of the history split view. Renders the current
//  clip's full body so the user can read long text without resorting
//  to Quick Look. Switches between three subviews based on clip type:
//  text (NSTextView), image (NSImageView), or an "empty" label.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class HistoryPreviewView: NSView {

    private let textScrollView = NSScrollView()
    private let textView = NSTextView()
    private let imageView = NSImageView()
    private let emptyLabel = NSTextField(labelWithString: "No preview")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        textScrollView.hasVerticalScroller = true
        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false

        // NSTextView inside an NSScrollView is sized by the scroll view via
        // the legacy autoresizing-mask path, so leave
        // translatesAutoresizingMaskIntoConstraints = true (the default).
        // Mixing it with .width-only autoresizing collapses the textView to
        // zero size and the preview reads as a blank pane.
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
        textView.backgroundColor = .controlBackgroundColor
        // Pin foreground to the dynamic .textColor so plain-text previews
        // adapt to dark mode (default is dynamic but can be overridden by a
        // prior RTF render — be explicit).
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textScrollView.documentView = textView

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        addSubview(textScrollView)
        addSubview(imageView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            textScrollView.topAnchor.constraint(equalTo: topAnchor),
            textScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        showEmpty()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Update the preview to match `entry`. Loads the underlying
    /// CPYClipData on the calling thread (main); the file is small per
    /// clip and is already cached by PasteService for paste paths.
    func show(entry: ClipboardHistoryEntry?) {
        guard let entry = entry else { showEmpty(); return }

        let type = NSPasteboard.PasteboardType(rawValue: entry.primaryType)

        // File / file-URL clips: show the file's icon plus its path so the
        // user can see what they're about to paste without opening it.
        if type == .deprecatedFilenames || type == .fileURL,
           let path = ClipboardHistoryCellView.firstFilePath(from: entry) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 256, height: 256)
            showImage(icon)
            return
        }

        guard let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: entry.dataPath) else {
            showEmpty()
            return
        }

        if type == .deprecatedTIFF || type == .tiff || type == .png, let image = clipData.image {
            showImage(image)
            return
        }

        // RTF/RTFD: render the styled bytes via NSAttributedString so the
        // pane shows formatting, not the plain-text fallback. RTFD lives in
        // the same RTFData blob (NSPasteboard normalises to RTF).
        if let rtfData = clipData.RTFData,
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            showAttributed(attributed)
            return
        }

        if !clipData.stringValue.isEmpty {
            showText(clipData.stringValue)
            return
        }

        // Unknown / empty payload: fall back to the entry's title so the
        // pane isn't blank for things like RTF without a string version.
        if !entry.displayTitle.isEmpty {
            showText(entry.displayTitle)
            return
        }

        showEmpty()
    }

    private func showText(_ string: String) {
        textView.isRichText = false
        textView.string = string
        textView.textColor = .textColor
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        textScrollView.isHidden = false
        imageView.isHidden = true
        emptyLabel.isHidden = true
    }

    private func showAttributed(_ string: NSAttributedString) {
        textView.isRichText = true
        // RTF carries explicit foreground colors (often black from rich
        // sources). On dark mode that renders unreadable, so swap blackish
        // / whitish foregrounds for the dynamic .textColor; non-monochrome
        // accents are preserved to keep visible color formatting.
        textView.textStorage?.setAttributedString(HistoryPreviewView.adaptForeground(string))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        textScrollView.isHidden = false
        imageView.isHidden = true
        emptyLabel.isHidden = true
    }

    static func adaptForeground(_ string: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: string)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
            let isMonochrome: Bool
            if let rgb = (value as? NSColor)?.usingColorSpace(.deviceRGB) {
                let red = rgb.redComponent
                let green = rgb.greenComponent
                let blue = rgb.blueComponent
                isMonochrome = abs(red - green) < 0.05 && abs(green - blue) < 0.05 && abs(red - blue) < 0.05
            } else {
                // Missing foreground or unknown color space — fall through to
                // the system default so the textView's own .textColor wins.
                isMonochrome = true
            }
            if isMonochrome {
                mutable.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            }
        }
        return mutable
    }

    private func showImage(_ image: NSImage) {
        imageView.image = image
        textScrollView.isHidden = true
        imageView.isHidden = false
        emptyLabel.isHidden = true
    }

    private func showEmpty() {
        textScrollView.isHidden = true
        imageView.isHidden = true
        imageView.image = nil
        emptyLabel.isHidden = false
    }
}
