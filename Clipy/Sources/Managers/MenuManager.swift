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

import Carbon
import Cocoa
import Magnet
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    fileprivate let snippetIcon = Asset.iconText.image
    // File path cache to avoid deserializing CPYClipData for file icons
    fileprivate var filePathCache = NSCache<NSString, NSString>()
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    fileprivate let menuRebuildSubject = PublishSubject<Void>()
    // Track currently open popup menu for dismissal on hotkey switch
    fileprivate weak var currentPopupMenu: NSMenu?
    fileprivate var pendingMenuType: MenuType?
    fileprivate var eventTap: CFMachPort?
    fileprivate var eventTapSource: CFRunLoopSource?
    fileprivate var currentMenuType: MenuType?
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
        filePathCache.countLimit = 200
    }

    func setup() {
        bind()
    }

}

// MARK: - Event Tap Callback
private func menuManagerEventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<MenuManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    guard manager.currentPopupMenu != nil else { return Unmanaged.passUnretained(event) }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    if let targetType = manager.menuTypeForCGEvent(keyCode: keyCode, flags: flags),
       targetType != manager.currentMenuType {
        manager.pendingMenuType = targetType
        manager.currentPopupMenu?.cancelTrackingWithoutAnimation()
        return nil
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Popup Menu
extension MenuManager {
    fileprivate func menuTypeForCGEvent(keyCode: Int64, flags: CGEventFlags) -> MenuType? {
        let hotKeyService = AppEnvironment.current.hotKeyService
        if matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: hotKeyService.mainKeyCombo) { return .main }
        if matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: hotKeyService.historyKeyCombo) { return .history }
        if matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: hotKeyService.snippetKeyCombo) { return .snippet }
        return nil
    }

    fileprivate func matchesCGEvent(keyCode: Int64, flags: CGEventFlags, keyCombo: KeyCombo?) -> Bool {
        guard let kc = keyCombo else { return false }
        guard keyCode == Int64(kc.currentKeyCode) else { return false }
        var carbonMods = 0
        if flags.contains(.maskCommand) { carbonMods |= cmdKey }
        if flags.contains(.maskAlternate) { carbonMods |= optionKey }
        if flags.contains(.maskControl) { carbonMods |= controlKey }
        if flags.contains(.maskShift) { carbonMods |= shiftKey }
        return carbonMods == kc.modifiers
    }

    private func installEventTap(for menuType: MenuType) {
        removeEventTap()
        currentMenuType = menuType
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: menuManagerEventTapCallback,
            userInfo: refcon
        ) else { return }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = eventTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            eventTapSource = nil
        }
        currentMenuType = nil
    }

    private func handlePendingMenu() {
        guard let next = pendingMenuType else { return }
        pendingMenuType = nil
        if next == .history {
            showClipboardHistoryWindow()
        } else {
            popUpMenu(next)
        }
    }

    func popUpMenu(_ type: MenuType) {
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = buildHistoryMenu()
        case .snippet:
            menu = buildSnippetMenu()
        }
        currentPopupMenu = menu
        pendingMenuType = nil
        installEventTap(for: type)
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        currentPopupMenu = nil
        removeEventTap()
        handlePendingMenu()
    }

    func showClipboardHistoryWindow() {
        currentPopupMenu?.cancelTrackingWithoutAnimation()
        currentPopupMenu = nil
        removeEventTap()
        pendingMenuType = nil
        CPYClipboardHistoryWindowController.sharedController.showWindow(self)
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        let folderMenu = NSMenu(title: folder.title)
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        var index = firstIndexOfMenuItems()
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        currentPopupMenu = folderMenu
        pendingMenuType = nil
        installEventTap(for: .snippet)
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        currentPopupMenu = nil
        removeEventTap()
        handlePendingMenu()
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

        let settings = MenuSettings()

        guard let clipMenu = clipMenu else { return }

        addHistoryItems(clipMenu, settings: settings)
        addSnippetItems(clipMenu, separateMenu: true, settings: settings)

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

    func buildHistoryMenu() -> NSMenu {
        let menu = NSMenu(title: Constants.Menu.history)
        addHistoryItems(menu, settings: MenuSettings())
        return menu
    }

    func buildSnippetMenu() -> NSMenu {
        let menu = NSMenu(title: Constants.Menu.snippet)
        addSnippetItems(menu, separateMenu: false, settings: MenuSettings())
        return menu
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
            let cacheKey = clip.dataPath as NSString
            let isMarkWithNumber = settings.isMarkWithNumber
            if let cached = filePathCache.object(forKey: cacheKey) {
                let icon = NSWorkspace.shared.icon(forFile: cached as String)
                MenuManager.setInlineImage(icon, on: menuItem, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber, imageHeight: 16)
            } else {
                let dataPath = clip.dataPath
                DispatchQueue.global(qos: .userInitiated).async { [weak self, weak menuItem] in
                    let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: dataPath)
                    guard let filePath = clipData?.fileNames.first else { return }
                    self?.filePathCache.setObject(filePath as NSString, forKey: cacheKey)
                    let icon = NSWorkspace.shared.icon(forFile: filePath)
                    DispatchQueue.main.async {
                        guard let menuItem = menuItem else { return }
                        MenuManager.setInlineImage(icon, on: menuItem, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber, imageHeight: 16)
                    }
                }
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
