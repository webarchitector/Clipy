//
//  AppDelegate.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import ServiceManagement
import RxCocoa
import RxSwift
import LoginServiceKit
import Magnet
import Screeen
import RxScreeen
import RealmSwift

private enum NetworkIsolation {
    private static let blockedSchemes = Set(["ftp", "ftps", "http", "https", "ws", "wss"])

    /// App Launcher's currency feature is the only outbound network egress
    /// in the entire process. Adding a host here is the only sanctioned way
    /// to pierce the otherwise process-wide URLProtocol block — see
    /// docs/superpowers/specs/2026-05-06-app-launcher-port-design.md.
    private static let allowedHosts: Set<String> = [
        "cdn.jsdelivr.net"
    ]

    static func configureProcess() {
        setenv("REALM_DISABLE_ANALYTICS", "1", 1)
        setenv("REALM_DISABLE_UPDATE_CHECKER", "1", 1)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0
        _ = URLProtocol.registerClass(RemoteNetworkBlockerURLProtocol.self)
    }

    static func shouldBlock(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        if let host = url?.host?.lowercased(), allowedHosts.contains(host) {
            return false
        }
        return blockedSchemes.contains(scheme)
    }
}

private final class RemoteNetworkBlockerURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        NetworkIsolation.shouldBlock(request.url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorDataNotAllowed,
                            userInfo: [NSLocalizedDescriptionKey: UpdateService.disabledMessage])
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}

@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    private var screenshotObserver: ScreenShotObserver?
    let disposeBag = DisposeBag()
    private var isSyncingLoginItemPreference = false

    override init() {
        NetworkIsolation.configureProcess()
        super.init()
    }

    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        // Migrate Realm
        Realm.migration()
    }

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            return AppEnvironment.current.menuManager.hasClips
        }
        return true
    }

    // MARK: - Class Methods
    static func storeTypesDictinary() -> [String: NSNumber] {
        var storeTypes = [String: NSNumber]()
        CPYClipData.availableTypesString.forEach { storeTypes[$0] = NSNumber(value: true) }
        return storeTypes
    }

    // MARK: - Menu Actions
    @objc func showPreferenceWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYPreferencesWindowController.sharedController.showWindow(self)
    }

    @objc func showSnippetEditorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYSnippetsEditorWindowController.sharedController.showWindow(self)
    }

    @objc func showClipboardHistoryWindow() {
        AppEnvironment.current.menuManager.showClipboardHistoryWindow()
    }

    @objc func terminate() {
        terminateApplication()
    }

    @objc func clearAllHistory() {
        let isShowAlert = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = L10n.clearHistory
            alert.informativeText = L10n.areYouSureYouWantToClearYourClipboardHistory
            alert.addButton(withTitle: L10n.clearHistory)
            alert.addButton(withTitle: L10n.cancel)
            alert.showsSuppressionButton = true

            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

            if alert.suppressionButton?.state == NSControl.StateValue.on {
                AppEnvironment.current.defaults.set(false, forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
            }
        }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance() else { return }
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: clip)
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance() else { return }
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
        AppEnvironment.current.pasteService.paste()
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = L10n.launchClipyOnSystemStartup
        alert.informativeText = L10n.youCanChangeThisSettingInThePreferencesIfYouWant
        alert.addButton(withTitle: L10n.launchOnSystemStartup)
        alert.addButton(withTitle: L10n.donTLaunch)
        alert.showsSuppressionButton = true
        NSApp.activate(ignoringOtherApps: true)

        //  Launch on system startup
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            setStoredLoginItemState(true)
            reflectLoginItemState()
        }
        // Do not show this message again
        if alert.suppressionButton?.state == NSControl.StateValue.on {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.suppressAlertForLoginItem)
        }
    }

    private func toggleAddingToLoginItems(_ isEnable: Bool) {
        if #available(macOS 13.0, *) {
            guard updateMainAppLoginItemState(to: isEnable) else {
                syncStoredLoginItemState()
                return
            }
            syncStoredLoginItemState()
            return
        }

        guard updateLegacyLoginItemState(to: isEnable) else {
            syncStoredLoginItemState()
            return
        }
        syncStoredLoginItemState()
    }

    private func updateLegacyLoginItemState(to isEnabled: Bool) -> Bool {
        let appPath = Bundle.main.bundlePath
        LoginServiceKit.removeLoginItems(at: appPath)
        guard isEnabled else { return true }
        return LoginServiceKit.addLoginItems(at: appPath)
    }

    @available(macOS 13.0, *)
    private func updateMainAppLoginItemState(to isEnabled: Bool) -> Bool {
        let service = SMAppService.mainApp

        if !isEnabled {
            let removedLegacy = updateLegacyLoginItemState(to: false)
            do {
                try service.unregister()
                return true
            } catch let error as NSError {
                if error.code == kSMErrorJobNotFound {
                    return removedLegacy
                }
                return false
            }
        }

        _ = updateLegacyLoginItemState(to: false)

        do {
            try service.register()
        } catch let error as NSError {
            if error.code == kSMErrorAlreadyRegistered {
                return true
            }
            // Unsigned local debug builds cannot use SMAppService; keep a legacy fallback.
            if error.code == kSMErrorInvalidSignature {
                return updateLegacyLoginItemState(to: true)
            }

            if service.status == .requiresApproval || error.code == kSMErrorLaunchDeniedByUser {
                showLoginItemApprovalAlert()
            }
            return false
        }

        if service.status == .requiresApproval {
            showLoginItemApprovalAlert()
        }
        return true
    }

    private func reflectLoginItemState() {
        let isInLoginItems = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem)
        toggleAddingToLoginItems(isInLoginItems)
    }

    private func syncStoredLoginItemState() {
        setStoredLoginItemState(systemLoginItemEnabledState())
    }

    private func setStoredLoginItemState(_ isEnabled: Bool) {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) != isEnabled else { return }

        isSyncingLoginItemPreference = true
        AppEnvironment.current.defaults.set(isEnabled, forKey: Constants.UserDefaults.loginItem)
        isSyncingLoginItemPreference = false
    }

    private func systemLoginItemEnabledState() -> Bool {
        let legacyLoginItemEnabled = LoginServiceKit.isExistLoginItems(at: Bundle.main.bundlePath)

        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                return true
            case .notRegistered, .notFound:
                return legacyLoginItemEnabled
            @unknown default:
                return legacyLoginItemEnabled
            }
        }

        return legacyLoginItemEnabled
    }

    private func showLoginItemApprovalAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.launchOnSystemStartup
        alert.informativeText = "Allow Clipy in System Settings > General > Login Items to finish enabling launch at login."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        syncStoredLoginItemState()
        // SDKs
        CPYUtilities.initSDKs()
        // Check Accessibility Permission
        AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: true)

        // Show Login Item
        if !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) && !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.suppressAlertForLoginItem) {
            promptToAddLoginItems()
        }

        // Binding Events
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.dataCleanService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.pasteService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()
        AppEnvironment.current.appLauncherService.setupHotKey()

        // Managers
        AppEnvironment.current.menuManager.setup()
    }
}

// MARK: - Bind
private extension AppDelegate {
    func bind() {
        // Login Item
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.loginItem, retainSelf: false)
            .compactMap { $0 }
            .subscribe(onNext: { [weak self] _ in
                guard let self = self, !self.isSyncingLoginItemPreference else { return }
                self.reflectLoginItemState()
            })
            .disposed(by: disposeBag)
        // Observe Screenshot — create observer lazily to avoid Desktop access prompt
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.Beta.observerScreenshot, retainSelf: false)
            .compactMap { $0 }
            .subscribe(onNext: { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    if self.screenshotObserver == nil {
                        let observer = ScreenShotObserver()
                        observer.rx.addedImage
                            .subscribe(onNext: { image in
                                AppEnvironment.current.clipService.create(with: image)
                            })
                            .disposed(by: self.disposeBag)
                        observer.start()
                        self.screenshotObserver = observer
                    }
                    self.screenshotObserver?.isEnabled = true
                } else {
                    self.screenshotObserver?.isEnabled = false
                }
            })
            .disposed(by: disposeBag)
    }
}
