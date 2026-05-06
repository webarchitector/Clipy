//
//  AppLauncherService.swift
//
//  Clipy AppLauncher — Magnet HotKey registration and lifecycle.
//

import Cocoa
import Magnet

final class AppLauncherService: NSObject {

    private static let identifier = "AppLauncherHotKey"
    private var keyCombo: KeyCombo?

    /// Called once from AppDelegate.applicationDidFinishLaunching. Pre-seeds
    /// the factory default ⌘Space if the user has never had a value
    /// archived (gated by Constants.HotKey.appLauncherDidPreSeed so a user
    /// who later clears the shortcut stays cleared).
    func setupHotKey() {
        let defaults = AppEnvironment.current.defaults
        if !defaults.bool(forKey: Constants.HotKey.appLauncherDidPreSeed) {
            // ⌘Space — kVK_Space = 49, cmdKey = 256 (Carbon).
            if let combo = KeyCombo(QWERTYKeyCode: 49, carbonModifiers: 256),
               let data = combo.archive() {
                defaults.set(data, forKey: Constants.HotKey.appLauncherKeyCombo)
            }
            defaults.set(true, forKey: Constants.HotKey.appLauncherDidPreSeed)
        }
        change(keyCombo: savedKeyCombo())
        AppLauncher.shared.preload()
    }

    /// Re-register when the user edits the shortcut from preferences.
    func change(keyCombo: KeyCombo?) {
        self.keyCombo = keyCombo

        if let data = keyCombo?.archive() {
            AppEnvironment.current.defaults.set(data, forKey: Constants.HotKey.appLauncherKeyCombo)
        } else {
            AppEnvironment.current.defaults.removeObject(forKey: Constants.HotKey.appLauncherKeyCombo)
        }

        HotKeyCenter.shared.unregisterHotKey(with: AppLauncherService.identifier)
        guard let keyCombo = keyCombo else { return }

        let hotKey = HotKey(identifier: AppLauncherService.identifier,
                            keyCombo: keyCombo,
                            target: self,
                            action: #selector(handleHotKey))
        let didRegister = hotKey.register()
        if !didRegister {
            NSLog("AppLauncherService: failed to register hotkey \(keyCombo)")
        }
    }

    /// Convenience accessor for the preferences UI.
    var currentKeyCombo: KeyCombo? { keyCombo }

    @objc private func handleHotKey() {
        DispatchQueue.main.async {
            AppLauncher.shared.toggle()
        }
    }

    private func savedKeyCombo() -> KeyCombo? {
        guard let data = AppEnvironment.current.defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo) else {
            return nil
        }
        return LegacyKeyedArchive.unarchivedObject(of: KeyCombo.self, from: data)
    }
}
