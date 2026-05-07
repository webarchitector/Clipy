//
//  MenuManager+MenuBuilders.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift

// MARK: - Cached Menu Settings
struct MenuSettings {
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
    let thumbnailWidth: Int
    let thumbnailHeight: Int

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
        thumbnailWidth = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        thumbnailHeight = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)
    }
}

// MARK: - Menus
extension MenuManager {
    func currentSettings() -> MenuSettings {
        if let cached = cachedSettings { return cached }
        let settings = MenuSettings()
        cachedSettings = settings
        return settings
    }

    func createClipMenu() {
        clipMenu = NSMenu(title: Constants.Application.name)

        let settings = currentSettings()

        guard let clipMenu = clipMenu else { return }
        // Install/remove the right-click tap for *both* entry points (status
        // item click & Cmd+Shift+V hotkey) — popUpMenu's explicit install only
        // covered the hotkey path.
        clipMenu.delegate = self

        addHistoryItems(clipMenu, settings: settings)
        addSnippetItems(clipMenu, separateMenu: true, settings: settings)

        clipMenu.addItem(NSMenuItem.separator())

        if settings.addClearHistoryMenuItem {
            clipMenu.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))
        }

        // ⌘F from inside the popup opens the searchable history window —
        // NSMenu's built-in type-to-search only highlights by prefix and is
        // capped at a 1-second buffer, so substring/multi-token search has
        // to live in the standalone window. The keyEquivalent fires while
        // the popup is up so the user reaches search without ever touching
        // the mouse.
        let searchItem = NSMenuItem(title: L10n.searchHistory + "...",
                                    action: #selector(AppDelegate.showClipboardHistoryWindow),
                                    keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = [.command]
        clipMenu.addItem(searchItem)
        clipMenu.addItem(NSMenuItem(title: L10n.editSnippets, action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu.addItem(NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu.addItem(NSMenuItem.separator())
        clipMenu.addItem(NSMenuItem(title: L10n.quitClipy, action: #selector(AppDelegate.terminate)))

        statusItem?.menu = clipMenu
    }

    func buildHistoryMenu() -> NSMenu {
        let menu = NSMenu(title: Constants.Menu.history)
        addHistoryItems(menu, settings: currentSettings())
        return menu
    }

    func buildSnippetMenu() -> NSMenu {
        let menu = NSMenu(title: Constants.Menu.snippet)
        addSnippetItems(menu, separateMenu: false, settings: currentSettings())
        return menu
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    static func setInlineImage(_ image: NSImage, on menuItem: NSMenuItem, listNumber: Int, isMarkWithNumber: Bool, imageHeight: CGFloat = 32, maxWidth: CGFloat? = nil) {
        let font = menuItem.menu?.font ?? NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString()
        if isMarkWithNumber {
            result.append(NSAttributedString(string: "\(listNumber). ", attributes: [.font: font]))
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        if let maxWidth, image.size.width > 0, image.size.height > 0 {
            let scale = min(maxWidth / image.size.width, imageHeight / image.size.height)
            displayWidth = image.size.width * scale
            displayHeight = image.size.height * scale
        } else {
            let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1
            displayWidth = aspect > 0 ? imageHeight / aspect : imageHeight
            displayHeight = imageHeight
        }
        attachment.bounds = CGRect(x: 0, y: font.descender, width: displayWidth, height: displayHeight)
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
extension MenuManager {
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
            // Wrap the non-Sendable NSMenuItem / NSImage refs in main-thread
            // boxes so Swift 6 strict concurrency lets us cross the cache's
            // async boundary. WeakBox preserves the prior `[weak menuItem]`
            // semantics — stale callbacks on a rebuilt menu drop quietly.
            let menuBox = MainThreadWeakBox(menuItem)
            ThumbnailCache.shared.object(forKeyAsync: clip.thumbnailPath) { image in
                guard let image = image else { return }
                let imageBox = MainThreadBox(image)
                DispatchQueue.main.async {
                    guard let menuItem = menuBox.value else { return }
                    let thumbW = CGFloat(max(16, settings.thumbnailWidth))
                    let thumbH = CGFloat(max(16, settings.thumbnailHeight))
                    MenuManager.setInlineImage(imageBox.value, on: menuItem, listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber, imageHeight: thumbH, maxWidth: thumbW)
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
                let menuBox = MainThreadWeakBox(menuItem)
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: dataPath)
                    guard let filePath = clipData?.fileNames.first else { return }
                    self?.filePathCache.setObject(filePath as NSString, forKey: cacheKey)
                    let icon = NSWorkspace.shared.icon(forFile: filePath)
                    let iconBox = MainThreadBox(icon)
                    DispatchQueue.main.async {
                        guard let menuItem = menuBox.value else { return }
                        MenuManager.setInlineImage(iconBox.value, on: menuItem, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber, imageHeight: 16)
                    }
                }
            }
        }

        return menuItem
    }
}

// MARK: - Snippets
extension MenuManager {
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
