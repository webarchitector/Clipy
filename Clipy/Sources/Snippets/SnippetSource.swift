import Foundation

enum SnippetSource: Int {
    case native = 0
    case appleNotes = 1
}

enum SnippetSourceStore {
    static var current: SnippetSource {
        get {
            let raw = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.snippetSource)
            return SnippetSource(rawValue: raw) ?? .native
        }
        set {
            AppEnvironment.current.defaults.set(newValue.rawValue, forKey: Constants.UserDefaults.snippetSource)
        }
    }

    static var appleNotesFolder: String? {
        get {
            let name = AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.appleNotesFolder)
            return (name?.isEmpty == false) ? name : nil
        }
        set {
            AppEnvironment.current.defaults.set(newValue ?? "", forKey: Constants.UserDefaults.appleNotesFolder)
        }
    }
}
