//
//  InputSourceService.swift
//
//  Clipy InputSource — Magnet hotkey registration per input source.
//
//  Each input source ID gets one stored KeyCombo in UserDefaults under a
//  per-source key ("kCPYInputSource_" + identifier-with-dots-replaced).
//  When triggered, the hotkey calls TISSelectInputSource for that source.
//

// swiftlint:disable identifier_name

import Cocoa
import Magnet

final class InputSourceService: NSObject {

    private struct Registration {
        let source: InputSource
        let identifier: String
        var keyCombo: KeyCombo?
    }

    private static let defaultsKeyPrefix = "kCPYInputSource_"
    private static let hotKeyIdentifierPrefix = "InputSource:"

    private var registrations: [String: Registration] = [:]

    /// Called once from AppDelegate.applicationDidFinishLaunching. For each
    /// available input source, look up a stored KeyCombo (if any) and
    /// register a Magnet hotkey that selects that source.
    func setupHotKeys() {
        for source in InputSource.sources {
            var combo = savedKeyCombo(forIdentifier: source.identifier)
            // Drop combos already claimed by an earlier source. Without this
            // dedup, a stale duplicate in defaults (manual plist edit, legacy
            // migration, two sources sharing a default combo) would silently
            // fail the second `HotKey.register()` and the zombie binding
            // would persist in defaults forever.
            if let existing = combo,
               registrations.contains(where: { $0.value.keyCombo == existing }) {
                AppEnvironment.current.defaults.removeObject(forKey: defaultsKey(for: source.identifier))
                NSLog("InputSourceService: cleared duplicate KeyCombo for \(source.identifier)")
                combo = nil
            }
            registrations[source.identifier] = Registration(
                source: source,
                identifier: hotKeyIdentifier(for: source.identifier),
                keyCombo: combo
            )
            registerIfNeeded(source: source, keyCombo: combo)
        }
    }

    /// Re-register when the user edits a source's shortcut from preferences.
    /// Passing `nil` clears the binding.
    func change(source: InputSource, keyCombo: KeyCombo?) {
        var registration = registrations[source.identifier]
            ?? Registration(source: source,
                            identifier: hotKeyIdentifier(for: source.identifier),
                            keyCombo: nil)
        registration.keyCombo = keyCombo
        registrations[source.identifier] = registration

        if let data = keyCombo?.archive() {
            AppEnvironment.current.defaults.set(data, forKey: defaultsKey(for: source.identifier))
        } else {
            AppEnvironment.current.defaults.removeObject(forKey: defaultsKey(for: source.identifier))
        }

        HotKeyCenter.shared.unregisterHotKey(with: registration.identifier)

        // De-duplicate: if another source had the same KeyCombo, drop it so
        // the new binding wins (matches selector HotKeyCenter behaviour).
        if let combo = keyCombo {
            for (otherID, other) in registrations where otherID != source.identifier {
                if other.keyCombo == combo {
                    var updated = other
                    updated.keyCombo = nil
                    registrations[otherID] = updated
                    AppEnvironment.current.defaults.removeObject(forKey: defaultsKey(for: otherID))
                    HotKeyCenter.shared.unregisterHotKey(with: other.identifier)
                }
            }
        }

        registerIfNeeded(source: source, keyCombo: keyCombo)
    }

    /// Convenience accessor for the preferences UI.
    func keyCombo(for source: InputSource) -> KeyCombo? {
        return registrations[source.identifier]?.keyCombo
    }

    // MARK: - Private

    private func registerIfNeeded(source: InputSource, keyCombo: KeyCombo?) {
        guard let combo = keyCombo else { return }
        let identifier = hotKeyIdentifier(for: source.identifier)
        let target = HotKeyTarget(source: source)
        registrations[source.identifier]?.keyCombo = combo
        // Retain the target — Magnet's HotKey takes a weak reference. We
        // store one HotKeyTarget per source on the registration so it stays
        // alive for the lifetime of the binding.
        let registration = Registration(source: source, identifier: identifier, keyCombo: combo)
        registrations[source.identifier] = registration

        let hotKey = HotKey(identifier: identifier,
                            keyCombo: combo,
                            target: target,
                            action: #selector(HotKeyTarget.fire))
        // Magnet retains the HotKey via HotKeyCenter; we don't need to hold
        // it ourselves. But we DO need to keep the target alive — store it
        // on the HotKey via objc_setAssociatedObject so Magnet's reference
        // to HotKey transitively keeps the target alive.
        objc_setAssociatedObject(hotKey, &HotKeyTarget.associationKey,
                                 target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if !hotKey.register() {
            NSLog("InputSourceService: failed to register hotkey for \(source.identifier)")
        }
    }

    private func savedKeyCombo(forIdentifier identifier: String) -> KeyCombo? {
        guard let data = AppEnvironment.current.defaults.data(forKey: defaultsKey(for: identifier)) else {
            return nil
        }
        return LegacyKeyedArchive.unarchivedObject(of: KeyCombo.self, from: data)
    }

    private func defaultsKey(for identifier: String) -> String {
        return InputSourceService.defaultsKeyPrefix + identifier.replacingOccurrences(of: ".", with: "-")
    }

    private func hotKeyIdentifier(for identifier: String) -> String {
        return InputSourceService.hotKeyIdentifierPrefix + identifier
    }
}

/// Per-source @objc target so Magnet's `target+selector` API can dispatch.
/// One instance per registered source. Retained by the HotKey via
/// objc_setAssociatedObject.
private final class HotKeyTarget: NSObject {
    static var associationKey: UInt8 = 0

    private let source: InputSource

    init(source: InputSource) {
        self.source = source
    }

    @objc func fire() {
        DispatchQueue.main.async { [source] in
            source.select()
        }
    }
}
