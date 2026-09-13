import AppKit
import Security

enum FeedbackKind: Int, CaseIterable {
    case bug, feedback, idea

    var title: String {
        switch self {
        case .bug: return "Bug"
        case .feedback: return "Feedback"
        case .idea: return "Idea"
        }
    }
    var label: String { title.lowercased() }
    var symbol: String {
        switch self {
        case .bug: return "ladybug"
        case .feedback: return "bubble.left"
        case .idea: return "lightbulb"
        }
    }
}

struct FeedbackReport {
    var kind: FeedbackKind
    var title: String
    var body: String
    var includeContext: Bool
    var documentURL: URL?

    var fullBody: String {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard includeContext else { return text }
        let info = BuildInfo.current
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        text += "\n\n---\n"
        text += "- MD Reader \(info.version) (\(info.build)), commit \(info.commit)\n"
        text += "- \(os)\n"
        if let url = documentURL {
            text += "- Document: `\(url.lastPathComponent)`\n"
        }
        return text
    }
}

/// Creates GitHub issues. Uses the REST API when a token is stored in the Keychain,
/// otherwise opens a prefilled "new issue" page in the browser.
enum GitHubFeedback {
    static let owner = "ljack"
    static let repo = "macos-md-reader"

    enum Outcome {
        case created(URL)
        case openedInBrowser
    }

    static func submit(_ report: FeedbackReport, completion: @escaping (Result<Outcome, Error>) -> Void) {
        guard let token = TokenStore.load(), !token.isEmpty else {
            openInBrowser(report)
            completion(.success(.openedInBrowser))
            return
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "title": report.title,
            "body": report.fullBody,
            "labels": [report.kind.label],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Outcome, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let urlString = json["html_url"] as? String, let url = URL(string: urlString) {
                result = .success(.created(url))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let message = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["message"] as? String
                result = .failure(NSError(domain: "GitHubFeedback", code: status, userInfo: [
                    NSLocalizedDescriptionKey: "GitHub returned \(status). \(message ?? "")".trimmingCharacters(in: .whitespaces),
                    NSLocalizedRecoverySuggestionErrorKey: "Check the token in the feedback sheet (needs `repo` or Issues write scope).",
                ]))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func openInBrowser(_ report: FeedbackReport) {
        var comps = URLComponents(string: "https://github.com/\(owner)/\(repo)/issues/new")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: report.title),
            URLQueryItem(name: "body", value: report.fullBody),
            URLQueryItem(name: "labels", value: report.kind.label),
        ]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }
}

/// Keychain-backed storage for the GitHub token.
enum TokenStore {
    private static let service = "fi.jarkkolietolahti.MDReader.github-token"
    private static let account = "github"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
