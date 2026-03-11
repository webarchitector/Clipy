//
//  UpdateService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by OpenAI Codex on 2026/03/09.
//

import Foundation

final class UpdateService {
    static let disabledMessage = "Network access is disabled in this build."

    init() {}

    func statusDescription() -> String {
        Self.disabledMessage
    }
}
