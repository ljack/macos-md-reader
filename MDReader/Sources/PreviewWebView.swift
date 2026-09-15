import Foundation
import UniformTypeIdentifiers
import WebKit

/// Hardened WebKit setup for the preview.
///
/// The page is loaded with an `mdres:///<document directory>/` base URL instead of `file:`.
/// The web content process therefore never touches the file system: every relative image,
/// video, audio or font in the document is fetched through `DocumentResourceHandler`, which
/// runs in the app, reads the file itself and only serves image/media/font content types.
/// `file:` URLs are not in the CSP at all.
enum PreviewWebView {
    static let scheme = "mdres"

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        // Web Inspector for the app's own UI. Content scripts cannot run anyway (CSP nonce).
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(DocumentResourceHandler(), forURLScheme: scheme)
        return config
    }

    /// `mdres:///Users/me/notes/` for `/Users/me/notes`. `nil` for untitled documents.
    static func baseURL(forDirectory dir: URL?) -> URL? {
        guard let dir else { return nil }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = ""
        var path = dir.standardizedFileURL.path
        if !path.hasSuffix("/") { path += "/" }
        comps.path = path
        return comps.url
    }

    /// The file an `mdres:` URL refers to.
    static func fileURL(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let path = url.path
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Serves document resources to the web view. Only files whose type conforms to image,
/// audiovisual content or font are readable; everything else is a 404 as far as the page
/// can tell. Supports `Range` so media playback works.
final class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    static let servableTypes: [UTType] = [.image, .audiovisualContent, .font]

    private let queue = DispatchQueue(label: "fi.jarkkolietolahti.MDReader.resources", qos: .userInitiated)
    private let lock = NSLock()
    private var active = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        lock.lock(); active.insert(id); lock.unlock()
        let request = task.request
        queue.async { [weak self] in
            guard let self else { return }
            let result = Self.load(request)
            DispatchQueue.main.async {
                self.lock.lock()
                let stillActive = self.active.remove(id) != nil
                self.lock.unlock()
                guard stillActive else { return }
                switch result {
                case .success(let (response, data)):
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                case .failure(let error):
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); active.remove(ObjectIdentifier(task)); lock.unlock()
    }

    // MARK: Loading

    static func isServable(_ fileURL: URL) -> Bool {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isRegularFileKey]),
              values.isDirectory != true, values.isRegularFile == true,
              let type = values.contentType else { return false }
        return servableTypes.contains(where: { type.conforms(to: $0) })
    }

    private static func load(_ request: URLRequest) -> Result<(URLResponse, Data), Error> {
        guard let url = request.url, let fileURL = PreviewWebView.fileURL(for: url), isServable(fileURL) else {
            return .failure(URLError(.fileDoesNotExist))
        }
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return .failure(URLError(.cannotOpenFile))
        }
        let mime = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredMIMEType) ?? "application/octet-stream"
        var headers: [String: String] = [
            "Content-Type": mime,
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
        if let range = request.value(forHTTPHeaderField: "Range"), let (lo, hi) = parseRange(range, total: data.count) {
            let slice = data.subdata(in: lo..<(hi + 1))
            headers["Content-Range"] = "bytes \(lo)-\(hi)/\(data.count)"
            headers["Content-Length"] = String(slice.count)
            guard let response = HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers) else {
                return .failure(URLError(.badServerResponse))
            }
            return .success((response, slice))
        }
        headers["Content-Length"] = String(data.count)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            return .failure(URLError(.badServerResponse))
        }
        return .success((response, data))
    }

    /// `bytes=a-b`, `bytes=a-`, `bytes=-n`. Returns inclusive bounds.
    static func parseRange(_ header: String, total: Int) -> (Int, Int)? {
        guard total > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return nil }
        let a = spec[..<dash], b = spec[spec.index(after: dash)...]
        if a.isEmpty {
            guard let n = Int(b), n > 0 else { return nil }
            return (max(0, total - n), total - 1)
        }
        guard let lo = Int(a), lo < total else { return nil }
        let hi = b.isEmpty ? total - 1 : min(Int(b) ?? -1, total - 1)
        guard hi >= lo else { return nil }
        return (lo, hi)
    }
}
