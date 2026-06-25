import Quick
import Nimble
import Foundation
import Carbon
import Magnet
@testable import Clipy

class AppLauncherServicePersistenceSpec: QuickSpec {
    override class func spec() {
        // Each test runs against an isolated NSUserDefaults suite so neither
        // global state nor a previous spec's leftovers leak in. We swap
        // `AppEnvironment.current.defaults` for the duration of the test
        // and restore it via `defer` — there's no per-spec teardown hook
        // under Swift 6 strict concurrency that lets us hold the original
        // defaults across `it` closures.

        func isolatedDefaults() -> UserDefaults {
            let suite = "com.clipy-app.Clipy.AppLauncherServiceSpec.\(UUID().uuidString)"
            UserDefaults().removePersistentDomain(forName: suite)
            return UserDefaults(suiteName: suite)!
        }

        // KeyCombo whose Carbon flags map to a real ⌘+Y. Picked to avoid
        // collisions with system or Clipy hotkeys when a real
        // HotKey.register() runs as a side effect of `change()`.
        func makeCombo() -> KeyCombo {
            return KeyCombo(QWERTYKeyCode: kVK_ANSI_Y, carbonModifiers: cmdKey)!
        }

        // Restore AppEnvironment after each test so subsequent specs see
        // the standard defaults again. HotKey side effects from
        // `change()` are unregistered explicitly with the service's
        // `change(keyCombo: nil)`.
        func swapEnvironment(to defaults: UserDefaults) -> () -> Void {
            let original = AppEnvironment.current.defaults
            AppEnvironment.replaceCurrent(defaults: defaults)
            return {
                AppEnvironment.replaceCurrent(defaults: original)
            }
        }

        describe("AppLauncherService.change") {

            it("persists an archived KeyCombo to defaults") {
                let defaults = isolatedDefaults()
                let restore = swapEnvironment(to: defaults)
                defer { restore() }

                let service = AppLauncherService()
                let combo = makeCombo()
                service.change(keyCombo: combo)
                defer { service.change(keyCombo: nil) }  // unregister hotkey

                let stored = defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo)
                expect(stored) != nil
                expect(service.currentKeyCombo) != nil
                expect(service.currentKeyCombo?.currentKeyCode) == combo.currentKeyCode
            }

            it("removes the persisted entry when the combo is cleared") {
                let defaults = isolatedDefaults()
                let restore = swapEnvironment(to: defaults)
                defer { restore() }

                let service = AppLauncherService()
                service.change(keyCombo: makeCombo())
                expect(defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo)) != nil

                service.change(keyCombo: nil)

                expect(defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo)) == nil
                expect(service.currentKeyCombo) == nil
            }
        }

        describe("AppLauncherService.setupHotKey") {

            it("pre-seeds the factory ⌘Space combo on first launch and marks it") {
                let defaults = isolatedDefaults()
                let restore = swapEnvironment(to: defaults)
                defer { restore() }

                let service = AppLauncherService()
                service.setupHotKey()
                defer { service.change(keyCombo: nil) }

                expect(defaults.bool(forKey: Constants.HotKey.appLauncherDidPreSeed)) == true
                expect(defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo)) != nil
                // The seeded combo is ⌘Space (kVK_Space = 49).
                expect(service.currentKeyCombo?.currentKeyCode) == 49
            }

            it("respects the pre-seed marker even when the user has cleared the combo") {
                let defaults = isolatedDefaults()
                let restore = swapEnvironment(to: defaults)
                defer { restore() }

                // Prior session: pre-seeded then user cleared it.
                defaults.set(true, forKey: Constants.HotKey.appLauncherDidPreSeed)
                expect(defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo)) == nil

                let service = AppLauncherService()
                service.setupHotKey()
                defer { service.change(keyCombo: nil) }

                // Cleared state must survive; we shouldn't re-seed.
                expect(defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo)) == nil
                expect(service.currentKeyCombo) == nil
            }

            it("preserves an already-archived combo across launches without overwriting") {
                let defaults = isolatedDefaults()
                let restore = swapEnvironment(to: defaults)
                defer { restore() }

                // Seed defaults with a non-default combo as if the user
                // had configured ⌘Y previously.
                let combo = makeCombo()
                guard let archived = combo.archive() else {
                    fail("KeyCombo.archive() returned nil")
                    return
                }
                defaults.set(archived, forKey: Constants.HotKey.appLauncherKeyCombo)
                defaults.set(true, forKey: Constants.HotKey.appLauncherDidPreSeed)

                let service = AppLauncherService()
                service.setupHotKey()
                defer { service.change(keyCombo: nil) }

                expect(service.currentKeyCombo?.currentKeyCode) == combo.currentKeyCode
            }
        }
    }
}
