import Foundation
import UniformTypeIdentifiers

/// Decides what a navigation inside the preview may do. Pure function, unit-tested.
///
/// The document is untrusted input. A link in it must never launch code or turn the reader
/// into a browser: http(s)/mailto go to the default handler, other Markdown files open as new
/// documents, ordinary files (images, PDFs, text…) open in their app, anything that could
/// execute (apps, scripts, `.command`, `.webloc`, archives, disk images…) is only revealed in
/// Finder. Navigations the user did not click (meta refresh, form posts) are blocked.
enum LinkPolicy {
    enum Action: Equatable {
        case allowInPage
        case openMarkdown(URL)
        case openFile(URL)
        case revealFile(URL)
        case openExternal(URL)
        case block
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn", "mkd", "mdwn", "mdtxt", "mdtext", "txt"]
    static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    /// Types handed to their default application when clicked.
    static let openableTypes: [UTType] = [.text, .image, .audiovisualContent, .pdf, .folder]
    /// Types never handed to another application from a click, even if they also match above.
    static let launchableTypes: [UTType] = [
        .executable, .script, .shellScript, .application, .applicationBundle, .bundle, .package,
        .internetLocation, .archive, .diskImage, .aliasFile, .symbolicLink,
    ]
    /// Extensions whose UTType conforms to something harmless-looking (XML, plist, text) but
    /// whose default handler launches, installs or configures something. Always only revealed.
    static let launchableExtensions: Set<String> = [
        "jnlp", "mobileconfig", "mobileprovision", "provisionprofile", "terminal", "url", "webloc",
        "inetloc", "fileloc", "ftploc", "afploc", "vncloc", "workflow", "wflow", "action", "app",
        "command", "tool", "sh", "zsh", "bash", "csh", "fish", "py", "rb", "pl", "php", "scpt",
        "scptd", "applescript", "jar", "pkg", "mpkg", "dmg", "iso", "img", "sparsebundle",
        "sparseimage", "kext", "plugin", "bundle", "qlgenerator", "saver", "prefpane", "service",
        "savedsearch", "safariextz", "xip", "cer", "crt", "der", "p12", "pfx", "pem", "keychain",
        "shortcut", "itermcolors", "reg", "bat", "cmd", "ps1", "vbs", "js", "jse", "hta", "msi", "exe",
    ]

    /// - Parameters:
    ///   - url: the navigation target.
    ///   - isLinkClick: `navigationType == .linkActivated` (or a `window.open`/`target=_blank`).
    ///   - base: the `mdres:` directory URL the page was loaded with (`PreviewWebView.baseURL`).
    static func action(for url: URL, isLinkClick: Bool, base: URL?) -> Action {
        if isSamePage(url, base: base) {
            if !isLinkClick || url.fragment != nil { return .allowInPage }
        }
        guard isLinkClick else {
            return url.absoluteString == "about:blank" ? .allowInPage : .block
        }
        if let file = PreviewWebView.fileURL(for: url) {
            return fileAction(file)
        }
        if url.isFileURL {
            return fileAction(url)
        }
        guard let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) else {
            return .block
        }
        return .openExternal(url)
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isSamePage(_ url: URL, base: URL?) -> Bool {
        guard let base, url.scheme?.lowercased() == base.scheme?.lowercased() else { return false }
        return directoryPath(url) == directoryPath(base)
    }

    private static func directoryPath(_ url: URL) -> String {
        var path = url.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func fileAction(_ url: URL) -> Action {
        if isMarkdown(url) { return .openMarkdown(url) }
        if launchableExtensions.contains(url.pathExtension.lowercased()) { return .revealFile(url) }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isExecutableKey, .isDirectoryKey, .isSymbolicLinkKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let isDirectory = values?.isDirectory ?? false
        if values?.isSymbolicLink == true { return .revealFile(url) }
        if !isDirectory, values?.isExecutable == true { return .revealFile(url) }
        guard let type else { return .revealFile(url) }
        if launchableTypes.contains(where: { type.conforms(to: $0) }) { return .revealFile(url) }
        if openableTypes.contains(where: { type.conforms(to: $0) }) { return .openFile(url) }
        return .revealFile(url)
    }
}
