//
//  CPYInputSourcesWindowController.swift
//
//  Standalone window that hosts CPYInputSourcesPreferenceViewController.
//  Reachable from the status-item menu ("Input Sources…").
//

import Cocoa

final class CPYInputSourcesWindowController: NSWindowController {

    static let sharedController: CPYInputSourcesWindowController = {
        let viewController = CPYInputSourcesPreferenceViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Input Sources"
        window.contentViewController = viewController
        window.center()
        let controller = CPYInputSourcesWindowController(window: window)
        return controller
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }
}
