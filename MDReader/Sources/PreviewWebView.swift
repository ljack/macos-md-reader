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

/// Serves document resources to the web view. Only files whose type (by extension) conforms to
/// image, audiovisual content or font are readable; everything else is a 404 as far as the page
/// can tell. The file is opened once (`O_NOFOLLOW`: the final path component may not be a
/// symlink) and validated with `fstat` on that descriptor, so the bytes served are the bytes
/// that were checked. Whole-file responses are capped; larger files are served only through
/// `Range` requests in bounded chunks, which is how WebKit fetches media anyway.
final class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    static let servableTypes: [UTType] = [.image, .audiovisualContent, .font]
    /// Largest file served in one response (images, fonts).
    static let maxWholeResponseBytes = 64 * 1024 * 1024
    /// Largest single `Range` response; the client asks again for the rest.
    static let maxRangeResponseBytes = 16 * 1024 * 1024
    /// Files above this are never served, range or not.
    static let maxFileBytes = 4 * 1024 * 1024 * 1024

    private let queue = DispatchQueue(label: "fi.jarkkolietolahti.MDReader.resources", qos: .userInitiated)
    private let lock = NSLock()
    private var active = Set<ObjectIdentifier>()

    private func isActive(_ id: ObjectIdentifier) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active.contains(id)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        lock.lock(); active.insert(id); lock.unlock()
        let request = task.request
        queue.async { [weak self] in
            guard let self, self.isActive(id) else { return }   // stopped before we got to it
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

    // MARK: Opening and validating

    struct OpenFile {
        let fd: Int32
        let size: Int
        let type: UTType
        func close() { Darwin.close(fd) }
    }

    /// Opens and validates in one step. `nil` when the file must not be served.
    static func openServable(_ fileURL: URL) -> OpenFile? {
        guard fileURL.isFileURL, !fileURL.pathExtension.isEmpty,
              let type = UTType(filenameExtension: fileURL.pathExtension),
              servableTypes.contains(where: { type.conforms(to: $0) }) else { return nil }
        let fd = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              st.st_size >= 0, st.st_size <= maxFileBytes else {
            Darwin.close(fd)
            return nil
        }
        return OpenFile(fd: fd, size: Int(st.st_size), type: type)
    }

    static func isServable(_ fileURL: URL) -> Bool {
        guard let file = openServable(fileURL) else { return false }
        file.close()
        return true
    }

    private static func read(_ file: OpenFile, from offset: Int, count: Int) -> Data? {
        var data = Data(count: count)
        var done = 0
        let ok: Bool = data.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return count == 0 }
            while done < count {
                let n = pread(file.fd, base + done, count - done, off_t(offset + done))
                if n <= 0 { return false }
                done += n
            }
            return true
        }
        return ok ? data : nil
    }

    private static func load(_ request: URLRequest) -> Result<(URLResponse, Data), Error> {
        guard let url = request.url, let fileURL = PreviewWebView.fileURL(for: url),
              let file = openServable(fileURL) else {
            return .failure(URLError(.fileDoesNotExist))
        }
        defer { file.close() }
        let mime = file.type.preferredMIMEType ?? "application/octet-stream"
        var headers: [String: String] = [
            "Content-Type": mime,
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
        if let range = request.value(forHTTPHeaderField: "Range"), let (lo, requestedHi) = parseRange(range, total: file.size) {
            let hi = min(requestedHi, lo + maxRangeResponseBytes - 1)
            guard let slice = read(file, from: lo, count: hi - lo + 1) else { return .failure(URLError(.cannotOpenFile)) }
            headers["Content-Range"] = "bytes \(lo)-\(hi)/\(file.size)"
            headers["Content-Length"] = String(slice.count)
            guard let response = HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers) else {
                return .failure(URLError(.badServerResponse))
            }
            return .success((response, slice))
        }
        guard file.size <= maxWholeResponseBytes else { return .failure(URLError(.dataLengthExceedsMaximum)) }
        guard let data = read(file, from: 0, count: file.size) else { return .failure(URLError(.cannotOpenFile)) }
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
        guard let lo = Int(a), lo >= 0, lo < total else { return nil }
        let hi = b.isEmpty ? total - 1 : min(Int(b) ?? -1, total - 1)
        guard hi >= lo else { return nil }
        return (lo, hi)
    }
}
