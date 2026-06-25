import Cocoa

final class ScratchEditorTextView: NSTextView {
    var onCommandEnter: (() -> Void)?
    var onDeleteNote: (() -> Void)?
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command {
            switch event.charactersIgnoringModifiers {
            case "\r":
                onCommandEnter?()
                return true
            case "\u{7f}", "\u{8}":
                onDeleteNote?()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
