//
//  HotKey.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon

public final class HotKey: NSObject {

    // MARK: - Properties
    public let identifier: String
    public let keyCombo: KeyCombo
    public let callback: ((HotKey) -> Void)?
    public let target: AnyObject?
    public let action: Selector?
    public let actionQueue: ActionQueue

    var hotKeyId: UInt32?
    var hotKeyRef: EventHotKeyRef?
    /// The CGKeyCode that Carbon was actually registered with at the time
    /// of `register()`. Stable across keyboard-layout changes — unlike
    /// `keyCombo.currentKeyCode`, which Sauce recomputes per call against
    /// the currently-active layout and can return a different value after
    /// the user switches between QWERTY/Russian/Dvorak/etc. HID-level
    /// dispatchers should match against this, not `currentKeyCode`.
    public internal(set) var registeredKeyCode: CGKeyCode?

    // MARK: - Enum Value
    public enum ActionQueue {
        case main
        case session

        public func execute(closure: @escaping () -> Void) {
            switch self {
            case .main:
                DispatchQueue.main.async {
                    closure()
                }
            case .session:
                closure()
            }
        }
    }

    // MARK: - Initialize
    public init(identifier: String, keyCombo: KeyCombo, target: AnyObject, action: Selector, actionQueue: ActionQueue = .main) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.callback = nil
        self.target = target
        self.action = action
        self.actionQueue = actionQueue
        super.init()
    }

    public init(identifier: String, keyCombo: KeyCombo, actionQueue: ActionQueue = .main, handler: @escaping ((HotKey) -> Void)) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.callback = handler
        self.target = nil
        self.action = nil
        self.actionQueue = actionQueue
        super.init()
    }

}

// MARK: - Invoke
public extension HotKey {
    func invoke() {
        guard let callback = self.callback else {
            guard let target = self.target as? NSObject, let selector = self.action else { return }
            guard target.responds(to: selector) else { return }
            actionQueue.execute { [weak self] in
                guard let wSelf = self else { return }
                target.perform(selector, with: wSelf)
            }
            return
        }
        actionQueue.execute { [weak self] in
            guard let wSelf = self else { return }
            callback(wSelf)
        }
    }
}

// MARK: - Register & UnRegister
public extension HotKey {
    @discardableResult
    func register() -> Bool {
        return HotKeyCenter.shared.register(with: self)
    }

    func unregister() {
        return HotKeyCenter.shared.unregister(with: self)
    }
}

// MARK: - override isEqual
public extension HotKey {
    override func isEqual(_ object: Any?) -> Bool {
        guard let hotKey = object as? HotKey else { return false }

        return self.identifier == hotKey.identifier &&
               self.keyCombo == hotKey.keyCombo &&
               self.hotKeyId == hotKey.hotKeyId &&
               self.hotKeyRef == hotKey.hotKeyRef
    }
}
