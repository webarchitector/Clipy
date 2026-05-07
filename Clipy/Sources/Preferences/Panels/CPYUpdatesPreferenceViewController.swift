//
//  CPYUpdatesPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

class CPYUpdatesPreferenceViewController: NSViewController {

    // MARK: - Properties
    @IBOutlet private weak var lastUpdateCheckTextField: NSTextField!
    @IBOutlet private weak var versionTextField: NSTextField!

    // MARK: - Initialize
    override func loadView() {
        super.loadView()
        versionTextField.stringValue = "v\(Bundle.main.appVersion ?? "")"
        lastUpdateCheckTextField.stringValue = "Network access is disabled in this build."
        hideNetworkControls()
    }

    // MARK: - Actions
    @IBAction private func checkForUpdates(_ sender: Any?) {
        _ = sender
    }

}

private extension CPYUpdatesPreferenceViewController {
    func hideNetworkControls() {
        view.subviews
            .compactMap { $0 as? NSControl }
            .filter { $0 !== versionTextField && $0 !== lastUpdateCheckTextField }
            .forEach { $0.isHidden = true }
    }
}
