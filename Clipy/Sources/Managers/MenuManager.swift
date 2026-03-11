//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    fileprivate let snippetIcon = Asset.iconText.image
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    fileprivate let menuRebuildSubject = PublishSubject<Void>()
    // Realm
    fileprivate var realm: Realm? = Realm.safeInstance()
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    func setup() {
        bind()
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        }
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func showClipboardHistoryWindow() {
        CPYClipboardHistoryWindowController.sharedController.showWindow(self)
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        let folderMenu = NSMenu(title: folder.title)
        // Folder title
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        // Snippets
        var index = firstIndexOfMenuItems()
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification (debounced to avoid repeated menu rebuilds)
        guard let realm = realm else { return }
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            self?.menuRebuildSubject.onNext(())
                        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            self?.menuRebuildSubject.onNext(())
                        }
        menuRebuildSubject
            .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings (consolidated)
        let defaults = AppEnvironment.current.defaults
        let boolKeys: [String] = [
            Constants.UserDefaults.addClearHistoryMenuItem,
            Constants.UserDefaults.showIconInTheMenu,
            Constants.UserDefaults.menuItemsTitleStartWithZero,
            Constants.UserDefaults.menuItemsAreMarkedWithNumbers,
            Constants.UserDefaults.showToolTipOnMenuItem,
            Constants.UserDefaults.showImageInTheMenu,
            Constants.UserDefaults.addNumericKeyEquivalents,
            Constants.UserDefaults.showColorPreviewInTheMenu,
            Constants.UserDefaults.reorderClipsAfterPasting
        ]
        let intKeys: [String] = [
            Constants.UserDefaults.maxHistorySize,
            Constants.UserDefaults.numberOfItemsPlaceInline,
            Constants.UserDefaults.numberOfItemsPlaceInsideFolder,
            Constants.UserDefaults.maxMenuItemTitleLength,
            Constants.UserDefaults.maxLengthOfToolTip
        ]
        let boolObservables = boolKeys.map { key in
            defaults.rx.observe(Bool.self, key, options: [.new], retainSelf: false)
                .compactMap { $0 }.distinctUntilChanged().map { _ in }
        }
        let intObservables = intKeys.map { key in
            defaults.rx.observe(Int.self, key, options: [.new], retainSelf: false)
                .compactMap { $0 }.distinctUntilChanged().map { _ in }
        }
        Observable.merge(boolObservables + intObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Cached Menu Settings
private struct MenuSettings {
    let isMarkWithNumber: Bool
    let isShowToolTip: Bool
    let isShowImage: Bool
    let isShowColorCode: Bool
    let addNumericKeyEquivalents: Bool
    let isStartFromZero: Bool
    let isShowIcon: Bool
    let maxLengthOfToolTip: Int
    let maxMenuItemTitleLength: Int
    let placeInLine: Int
    let placeInsideFolder: Int
    let maxHistory: Int
    let reorderClipsAfterPasting: Bool
    let addClearHistoryMenuItem: Bool

    init() {
        let defaults = AppEnvironment.current.defaults
        isMarkWithNumber = defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        isShowToolTip = defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        isShowImage = defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        isShowColorCode = defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        addNumericKeyEquivalents = defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)
        isStartFromZero = defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        isShowIcon = defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)
        maxLengthOfToolTip = defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
        maxMenuItemTitleLength = defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        placeInLine = defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        placeInsideFolder = defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        maxHistory = defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        reorderClipsAfterPasting = defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        addClearHistoryMenuItem = defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem)
    }
}

// MARK: - Menus
private extension MenuManager {
     func createClipMenu() {
        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)

        let settings = MenuSettings()

        guard let clipMenu = clipMenu, let historyMenu = historyMenu, let snippetMenu = snippetMenu else { return }

        addHistoryItems(clipMenu, settings: settings)
        addHistoryItems(historyMenu, settings: settings)

        addSnippetItems(clipMenu, separateMenu: true, settings: settings)
        addSnippetItems(snippetMenu, separateMenu: false, settings: settings)

        clipMenu.addItem(NSMenuItem.separator())

        if settings.addClearHistoryMenuItem {
            clipMenu.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))
        }

        clipMenu.addItem(NSMenuItem(title: L10n.searchHistory + "...",
                                     action: #selector(AppDelegate.showClipboardHistoryWindow)))
        clipMenu.addItem(NSMenuItem(title: L10n.editSnippets, action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu.addItem(NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu.addItem(NSMenuItem.separator())
        clipMenu.addItem(NSMenuItem(title: L10n.quitClipy, action: #selector(AppDelegate.terminate)))

        statusItem?.menu = clipMenu
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    static func setInlineImage(_ image: NSImage, on menuItem: NSMenuItem, listNumber: Int, isMarkWithNumber: Bool, imageHeight: CGFloat = 32) {
        let font = menuItem.menu?.font ?? NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString()
        if isMarkWithNumber {
            result.append(NSAttributedString(string: "\(listNumber). ", attributes: [.font: font]))
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Scale proportionally to requested height
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1
        let imageWidth = aspect > 0 ? imageHeight / aspect : imageHeight
        attachment.bounds = CGRect(x: 0, y: font.descender, width: imageWidth, height: imageHeight)
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
        let prefix = "\(listNumber). "
        let titleOnly = menuItem.title.hasPrefix(prefix) ? String(menuItem.title.dropFirst(prefix.count)) : menuItem.title
        result.append(NSAttributedString(string: titleOnly, attributes: [.font: font]))
        menuItem.attributedTitle = result
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let menuItemTitle = "\(count + 1) - \(lastNumber)"
        return makeSubmenuItem(menuItemTitle)
    }

    func makeSubmenuItem(_ title: String, isShowIcon: Bool? = nil) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        let showIcon = isShowIcon ?? AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)
        subMenuItem.image = showIcon ? folderIcon : nil
        return subMenuItem
    }

    func incrementListNumber(_ listNumber: NSInteger, max: NSInteger, start: NSInteger) -> NSInteger {
        var listNumber = listNumber + 1
        if listNumber == max && max == 10 && start == 1 {
            listNumber = 0
        }
        return listNumber
    }

    func trimTitle(_ title: String?, maxLength: Int? = nil) -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return "" }

        let firstLine = title.prefix(while: { !$0.isNewline })
        var titleString = String(firstLine)

        var maxLen = maxLength ?? AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if maxLen < shortenSymbol.count { maxLen = shortenSymbol.count }

        if titleString.count > maxLen {
            titleString = String(titleString.prefix(maxLen - shortenSymbol.count)) + shortenSymbol
        }

        return titleString
    }
}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu, settings: MenuSettings) {
        let placeInLine = settings.placeInLine
        let placeInsideFolder = settings.placeInsideFolder
        let maxHistory = settings.maxHistory
        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        // History
        let firstIndex = settings.isStartFromZero ? 0 : 1
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        var subMenuIndex = 1 + placeInLine

        let ascending = !settings.reorderClipsAfterPasting
        guard let realm = realm else { return }
        let clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        let currentSize = Int(clipResults.count)
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                // Folder
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount, start: firstIndex, end: currentSize, numberOfItems: placeInsideFolder)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                }

                // Clip
                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber, settings: settings)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                // Clip
                let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber, settings: settings)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }

            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }

            if maxHistory <= i { break }
        }
    }

    func makeClipMenuItem(_ clip: CPYClip, index: Int, listNumber: Int, settings: MenuSettings) -> NSMenuItem {
        var keyEquivalent = ""

        if settings.addNumericKeyEquivalents && (index <= kMaxKeyEquivalents) {
            var shortCutNumber = (settings.isStartFromZero) ? index : index + 1
            if shortCutNumber == kMaxKeyEquivalents {
                shortCutNumber = 0
            }
            keyEquivalent = "\(shortCutNumber)"
        }

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = trimTitle(clipString, maxLength: settings.maxMenuItemTitleLength)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        menuItem.representedObject = clip.dataHash

        if settings.isShowToolTip {
            menuItem.toolTip = String(clipString.prefix(settings.maxLengthOfToolTip))
        }

        if primaryPboardType == .deprecatedTIFF {
            menuItem.title = menuItemTitle("(Image)", listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)
        } else if primaryPboardType == .deprecatedPDF {
            menuItem.title = menuItemTitle("(PDF)", listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)
        } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
            menuItem.title = menuItemTitle("(Filenames)", listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)
        }

        let showThumbnail = !clip.thumbnailPath.isEmpty &&
            ((!clip.isColorCode && settings.isShowImage) || (clip.isColorCode && settings.isShowColorCode))
        if showThumbnail {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    guard let menuItem = menuItem, let image = object as? NSImage else { return }
                    MenuManager.setInlineImage(image, on: menuItem, listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber, imageHeight: 32)
                }
            }
        } else if settings.isShowIcon && (primaryPboardType == .deprecatedFilenames || primaryPboardType == .fileURL) {
            // Show system file icon for copied files without image thumbnail
            let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: clip.dataPath)
            if let filePath = clipData?.fileNames.first {
                let icon = NSWorkspace.shared.icon(forFile: filePath)
                MenuManager.setInlineImage(icon, on: menuItem, listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber, imageHeight: 16)
            }
        }

        return menuItem
    }
}

// MARK: - Snippets
private extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool, settings: MenuSettings) {
        guard let realm = realm else { return }
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        guard !folderResults.isEmpty else { return }
        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Snippet title
        let labelItem = NSMenuItem(title: L10n.snippet, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        var subMenuIndex = menu.numberOfItems - 1
        let firstIndex = settings.isStartFromZero ? 0 : 1

        folderResults
            .filter { $0.enable }
            .forEach { folder in
                let folderTitle = folder.title
                let subMenuItem = makeSubmenuItem(folderTitle, isShowIcon: settings.isShowIcon)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                var i = firstIndex
                folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .filter { $0.enable }
                    .forEach { snippet in
                        let subMenuItem = makeSnippetMenuItem(snippet, listNumber: i, settings: settings)
                        if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                            subMenu.addItem(subMenuItem)
                            i += 1
                        }
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int, settings: MenuSettings? = nil) -> NSMenuItem {
        let isMarkWithNumber = settings?.isMarkWithNumber ?? AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = settings?.isShowIcon ?? AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title, maxLength: settings?.maxMenuItemTitleLength)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.identifier
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = Asset.statusbarMenuBlack.image
        case .white:
            image = Asset.statusbarMenuWhite.image
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = clipMenu
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}

private struct ClipboardHistoryEntry: Equatable {
    let primaryKey: String
    let displayTitle: String
    let searchText: String
    let toolTip: String
    let thumbnailPath: String
    let isColorCode: Bool
    let dataPath: String
    let primaryType: String

    init(clip: CPYClip) {
        primaryKey = clip.dataHash
        thumbnailPath = clip.thumbnailPath
        isColorCode = clip.isColorCode
        dataPath = clip.dataPath
        primaryType = clip.primaryType

        // Use title stored in Realm (already contains preferredTitle from ClipService.save)
        let clipTitle = ClipboardHistoryEntry.sanitizedStoredTitle(clip.title)

        let rawTitle: String
        if clipTitle.isEmpty {
            rawTitle = ClipboardHistoryEntry.fallbackTitle(for: clip)
        } else {
            rawTitle = clipTitle
        }
        // Collapse whitespace/newlines into single line and limit length for display
        let singleLine = rawTitle.components(separatedBy: .newlines)
            .joined(separator: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        displayTitle = String(singleLine.prefix(500))

        searchText = displayTitle
        toolTip = String(displayTitle.prefix(2000))
    }

    private static func fallbackTitle(for clip: CPYClip) -> String {
        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipTitle = sanitizedStoredTitle(clip.title)
        if !clipTitle.isEmpty {
            return clipTitle
        }

        switch primaryPboardType {
        case .deprecatedTIFF, .tiff, .png:
            return "(Image)"
        case .deprecatedPDF, .pdf:
            return "(PDF)"
        case .deprecatedFilenames, .fileURL:
            return "(File)"
        case .deprecatedURL, .URL:
            return "(URL)"
        default:
            return ""
        }
    }

    private static func sanitizedStoredTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !["(Text)", "(Filenames)"].contains(trimmedTitle) else { return "" }
        return trimmedTitle
    }
}

private final class ClipboardHistoryTableView: NSTableView {
    var confirmHandler: (() -> Void)?
    var cancelHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        super.mouseDown(with: event)

        guard event.clickCount == 1 else { return }
        guard clickedRow >= 0, selectedRow == clickedRow else { return }
        confirmHandler?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            confirmHandler?()
        case 53:
            cancelHandler?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ClipboardHistoryCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipboardHistoryCellView")

    private let thumbnailView: NSImageView = {
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 4
        iv.layer?.masksToBounds = true
        return iv
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

    func configure(with entry: ClipboardHistoryEntry) {
        titleField.stringValue = entry.displayTitle
        titleField.toolTip = entry.toolTip

        if !entry.thumbnailPath.isEmpty {
            // Show cached thumbnail (image preview or color code)
            PINCache.shared.object(forKeyAsync: entry.thumbnailPath) { [weak self] _, _, object in
                DispatchQueue.main.async {
                    guard let self = self, let image = object as? NSImage else { return }
                    self.showThumbnail(image)
                }
            }
        } else if let filePath = ClipboardHistoryCellView.firstFilePath(from: entry) {
            // Show system file icon for copied files
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

    static func firstFilePath(from entry: ClipboardHistoryEntry) -> String? {
        let ptype = NSPasteboard.PasteboardType(rawValue: entry.primaryType)
        guard ptype == .deprecatedFilenames || ptype == .fileURL else { return nil }
        let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: entry.dataPath)
        return clipData?.fileNames.first
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hideThumbnail()
    }
}

private final class CPYClipboardHistoryWindowController: NSWindowController {
    static let sharedController = CPYClipboardHistoryWindowController()

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = ClipboardHistoryTableView()
    private let emptyStateLabel = NSTextField(labelWithString: L10n.noMatchingHistoryItems)
    private var realm: Realm? = Realm.safeInstance()

    private var clipToken: NotificationToken?
    private var workspaceObserver: NSObjectProtocol?
    private var entries = [ClipboardHistoryEntry]()
    private var filteredEntries = [ClipboardHistoryEntry]()
    private var returnApplication: NSRunningApplication?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        super.init(window: window)
        configureWindow()
        configureContentView()
        observeWorkspace()
        observeClips()
        reloadEntries()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clipToken?.invalidate()
        if let workspaceObserver = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        rememberReturnApplication(NSWorkspace.shared.frontmostApplication)
        searchField.stringValue = ""
        reloadEntries()
        super.showWindow(sender)
        window?.backgroundColor = .windowBackgroundColor
        CPYUtilities.presentHistoryWindow(window)
        window?.makeFirstResponder(searchField)
    }
}

private extension CPYClipboardHistoryWindowController {
    func configureWindow() {
        window?.title = L10n.history
        window?.delegate = self
        window?.backgroundColor = .windowBackgroundColor
        window?.collectionBehavior = .canJoinAllSpaces
        window?.minSize = NSSize(width: 420, height: 320)
        window?.setFrameAutosaveName("CPYClipboardHistoryWindow")
        window?.center()
    }

    func configureContentView() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.searchHistory
        searchField.delegate = self

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        tableColumn.resizingMask = .autoresizingMask
        tableColumn.width = 480

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 72
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .controlBackgroundColor
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(confirmSelection(_:))
        tableView.confirmHandler = { [weak self] in
            self?.confirmSelection(nil)
        }
        tableView.cancelHandler = { [weak self] in
            self?.close()
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.documentView = tableView

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.isHidden = true

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyStateLabel)

        window?.contentView = contentView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 16),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -16)
        ])
    }

    func observeClips() {
        guard let realm = realm else { return }
        clipToken = realm.objects(CPYClip.self).observe { [weak self] _ in
            self?.reloadEntries()
        }
    }

    func observeWorkspace() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                              object: nil,
                                                                              queue: .main) { [weak self] notification in
            let application = notification.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication
            self?.rememberReturnApplication(application)
        }
    }

    func rememberReturnApplication(_ application: NSRunningApplication?) {
        guard let application = application else { return }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        returnApplication = application
    }

    func reloadEntries() {
        guard let realm = realm else { return }
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        entries = realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
            .map(ClipboardHistoryEntry.init)
        applyFilter(searchField.stringValue)
    }

    func applyFilter(_ query: String) {
        let selectedPrimaryKey = selectedEntry?.primaryKey
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter {
                $0.searchText.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }

        tableView.reloadData()
        updateEmptyState()
        restoreSelection(primaryKey: selectedPrimaryKey)
    }

    func updateEmptyState() {
        let isEmpty = filteredEntries.isEmpty
        scrollView.isHidden = isEmpty
        emptyStateLabel.isHidden = !isEmpty
    }

    func restoreSelection(primaryKey: String?) {
        guard !filteredEntries.isEmpty else {
            tableView.deselectAll(nil)
            return
        }

        if let primaryKey = primaryKey,
           let row = filteredEntries.firstIndex(where: { $0.primaryKey == primaryKey }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    var selectedEntry: ClipboardHistoryEntry? {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < filteredEntries.count else { return nil }
        return filteredEntries[selectedRow]
    }

    @objc func confirmSelection(_ sender: Any?) {
        guard let entry = selectedEntry ?? filteredEntries.first else {
            NSSound.beep()
            return
        }

        guard let realm = Realm.safeInstance() else { return }
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: entry.primaryKey) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: clip)

        close()
    }
}

extension CPYClipboardHistoryWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        searchField.stringValue = ""
        returnApplication = nil
        CPYUtilities.closeHistoryWindow()
    }
}

extension CPYClipboardHistoryWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            confirmSelection(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !filteredEntries.isEmpty else { return true }
            let row = max(tableView.selectedRow, 0)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            window?.makeFirstResponder(tableView)
            return true
        default:
            return false
        }
    }
}

extension CPYClipboardHistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let cellView = (tableView.makeView(withIdentifier: ClipboardHistoryCellView.reuseIdentifier, owner: nil) as? ClipboardHistoryCellView)
            ?? ClipboardHistoryCellView(frame: .zero)
        cellView.configure(with: entry)
        return cellView
    }
}
