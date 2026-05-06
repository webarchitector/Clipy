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
import Combine

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
    var cancellables: Set<AnyCancellable> = []
    let notificationCenter = NotificationCenter.default
    let kMaxKeyEquivalents = 10
    let shortenSymbol = "..."
    let menuRebuildSubject = PassthroughSubject<Void, Never>()
    // Track currently open popup menu for dismissal on hotkey switch
    weak var currentPopupMenu: NSMenu?
    var pendingMenuType: MenuType?
    var pendingAppLauncher = false
    var pendingRebuild = false
    var eventTap: CFMachPort?
    var eventTapSource: CFRunLoopSource?
    var localEventMonitor: Any?
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
        manager.pendingAppLauncher = false
        manager.currentPopupMenu?.cancelTrackingWithoutAnimation()
        return nil
    }

    if let launcherCombo = AppEnvironment.current.appLauncherService.currentKeyCombo,
       manager.matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: launcherCombo) {
        manager.pendingMenuType = nil
        manager.pendingAppLauncher = true
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
        // Local monitor — fires for keyDown events within Clipy's own process,
        // including events delivered to NSMenu popups in tracking mode. Works
        // without Accessibility (unlike CGEvent.tapCreate).
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.currentPopupMenu != nil else { return event }
            let keyCode = Int64(event.keyCode)
            let flags = self.cgFlags(from: event.modifierFlags)
            if let target = self.menuTypeForCGEvent(keyCode: keyCode, flags: flags),
               target != self.currentMenuType {
                self.pendingMenuType = target
                self.pendingAppLauncher = false
                self.currentPopupMenu?.cancelTrackingWithoutAnimation()
                return nil
            }
            if let launcherCombo = AppEnvironment.current.appLauncherService.currentKeyCombo,
               self.matchesCGEvent(keyCode: keyCode, flags: flags, keyCombo: launcherCombo) {
                self.pendingMenuType = nil
                self.pendingAppLauncher = true
                self.currentPopupMenu?.cancelTrackingWithoutAnimation()
                return nil
            }
            return event
        }
        // CGEvent tap is the kernel-level fallback; only succeeds when the
        // user has granted Accessibility. Both can coexist — the local
        // monitor short-circuits in-process events first.
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

    /// Translate AppKit's `NSEvent.ModifierFlags` to the CGEventFlags shape
    /// `matchesCGEvent` expects, so the local-monitor and CGEventTap paths
    /// share the exact same key-combo detection logic.
    private func cgFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    private func removeEventTap() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
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
        if pendingAppLauncher {
            pendingAppLauncher = false
            AppLauncher.shared.toggle()
            return
        }
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
        // If the standalone history window is up, hide it synchronously
        // (orderOut, not close) so the new popup actually appears as the
        // focal UI. close() schedules animation that may run after popUp(),
        // which itself blocks the main runloop.
        let historyController = CPYClipboardHistoryWindowController.sharedController
        if historyController.isWindowLoaded, historyController.window?.isVisible == true {
            historyController.window?.orderOut(nil)
        }
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

    /// Close any Clipy-driven popup menu or window so a different UI surface
    /// (e.g. the AppLauncher panel) can take focus cleanly. Called from
    /// hotkey handlers that own a competing window.
    func dismissAllPopups() {
        currentPopupMenu?.cancelTrackingWithoutAnimation()
        currentPopupMenu = nil
        removeEventTap()
        pendingMenuType = nil
        let history = CPYClipboardHistoryWindowController.sharedController
        if history.isWindowLoaded, history.window?.isVisible == true {
            history.close()
        }
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
            self.menuRebuildSubject.send(())
        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            self?.menuRebuildSubject.send(())
                        }
        menuRebuildSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                if self.currentPopupMenu != nil {
                    self.pendingRebuild = true
                    return
                }
                self.createClipMenu()
            }
            .store(in: &cancellables)
        // Menu icon — boolean/integer publisher emits initial value via prepend
        // so the icon shows up at launch (matches RxSwift KVO semantics).
        let defaults = AppEnvironment.current.defaults
        defaults.integerPublisher(forKey: Constants.UserDefaults.showStatusItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            }
            .store(in: &cancellables)
        // Edit snippets
        notificationCenter
            .publisher(for: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.createClipMenu()
            }
            .store(in: &cancellables)
        // Observe change preference settings (consolidated): rebuild the menu
        // when any of these keys change. Fingerprint the watched values so a
        // change to an unrelated default doesn't trigger a useless rebuild.
        let watchedBoolKeys: [String] = [
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
        let watchedIntKeys: [String] = [
            Constants.UserDefaults.maxHistorySize,
            Constants.UserDefaults.numberOfItemsPlaceInline,
            Constants.UserDefaults.numberOfItemsPlaceInsideFolder,
            Constants.UserDefaults.maxMenuItemTitleLength,
            Constants.UserDefaults.maxLengthOfToolTip
        ]
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .map { _ -> [Int] in
                let bools = watchedBoolKeys.map { defaults.bool(forKey: $0) ? 1 : 0 }
                let ints = watchedIntKeys.map { defaults.integer(forKey: $0) }
                return bools + ints
            }
            .removeDuplicates()
            .dropFirst()  // initial state already used by createClipMenu in clipToken.observe
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.cachedSettings = nil
                self?.createClipMenu()
            }
            .store(in: &cancellables)
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
