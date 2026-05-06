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
import RealmSwift
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    var clipMenu: NSMenu?
    // StatusMenu
    var statusItem: NSStatusItem?
    // Icon Cache
    let folderIcon = Asset.iconFolder.image
    let snippetIcon = Asset.iconText.image
    // File path cache to avoid deserializing CPYClipData for file icons
    var filePathCache = NSCache<NSString, NSString>()
    // Other
    let disposeBag = DisposeBag()
    let notificationCenter = NotificationCenter.default
    let kMaxKeyEquivalents = 10
    let shortenSymbol = "..."
    let menuRebuildSubject = PublishSubject<Void>()
    // Track currently open popup menu for dismissal on hotkey switch
    weak var currentPopupMenu: NSMenu?
    var pendingMenuType: MenuType?
    var pendingRebuild = false
    var eventTap: CFMachPort?
    var eventTapSource: CFRunLoopSource?
    var currentMenuType: MenuType?
    // Realm
    var realm: Realm? = Realm.safeInstance()
    var clipToken: NotificationToken?
    var snippetToken: NotificationToken?
    // Cached defaults snapshot used during menu builds — invalidated when an observed key changes
    var cachedSettings: MenuSettings?
    // Cached clip-emptiness flag for cheap menu validation (avoids per-validate Realm query)
    private(set) var hasClips: Bool = false

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
    func menuTypeForCGEvent(keyCode: Int64, flags: CGEventFlags) -> MenuType? {
        let hotKeyService = AppEnvironment.current.hotKeyService
        if matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: hotKeyService.mainKeyCombo) { return .main }
        if matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: hotKeyService.historyKeyCombo) { return .history }
        if matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: hotKeyService.snippetKeyCombo) { return .snippet }
        return nil
    }

    func matchesCGEvent(keyCode: Int64, flags: CGEventFlags, keyCombo: KeyCombo?) -> Bool {
        guard let combo = keyCombo else { return false }
        guard keyCode == Int64(combo.currentKeyCode) else { return false }
        var carbonMods = 0
        if flags.contains(.maskCommand) { carbonMods |= cmdKey }
        if flags.contains(.maskAlternate) { carbonMods |= optionKey }
        if flags.contains(.maskControl) { carbonMods |= controlKey }
        if flags.contains(.maskShift) { carbonMods |= shiftKey }
        return carbonMods == combo.modifiers
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

    private func flushPendingRebuildIfNeeded() {
        guard pendingRebuild, currentPopupMenu == nil else { return }
        pendingRebuild = false
        createClipMenu()
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
        flushPendingRebuildIfNeeded()
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
        let settings = currentSettings()
        var index = settings.isStartFromZero ? 0 : 1
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index, settings: settings)
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
        flushPendingRebuildIfNeeded()
    }
}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification (debounced to avoid repeated menu rebuilds)
        guard let realm = realm else { return }
        let clips = realm.objects(CPYClip.self)
        hasClips = !clips.isEmpty
        clipToken = clips.observe { [weak self] change in
            guard let self = self else { return }
            switch change {
            case .initial(let results), .update(let results, _, _, _):
                self.hasClips = !results.isEmpty
            case .error:
                break
            }
            self.menuRebuildSubject.onNext(())
        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            self?.menuRebuildSubject.onNext(())
                        }
        menuRebuildSubject
            .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                guard let self = self else { return }
                if self.currentPopupMenu != nil {
                    self.pendingRebuild = true
                    return
                }
                self.createClipMenu()
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
                self?.cachedSettings = nil
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
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
