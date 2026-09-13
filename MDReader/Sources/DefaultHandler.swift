import AppKit
import UniformTypeIdentifiers

enum DefaultHandler {
    static let markdownType: UTType = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText

    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: markdownType) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault(completion: @escaping ((any Error)?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdownType) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    private static let askedKey = "DefaultHandler.asked"

    static func offerToBecomeDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey), !isDefault else { return }
        defaults.set(true, forKey: askedKey)

        let alert = NSAlert()
        alert.messageText = "Make MD Reader your default Markdown viewer?"
        alert.informativeText = "Markdown files (.md, .markdown) will open in MD Reader when double-clicked in Finder. You can change this later from the MD Reader menu."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        makeDefault { error in
            if let error { NSAlert(error: error).runModal() }
        }
    }
}
