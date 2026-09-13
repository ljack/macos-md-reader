import Foundation

/// Provenance stamped into Info.plist by Scripts/stamp-build.sh at build time.
struct BuildInfo {
    let version: String
    let build: String
    let commit: String
    let branch: String
    let buildDate: String

    static let current: BuildInfo = {
        let info = Bundle.main.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            commit: info["GitCommit"] as? String ?? "unknown",
            branch: info["GitBranch"] as? String ?? "unknown",
            buildDate: info["BuildDate"] as? String ?? "unknown")
    }()

    var isDirty: Bool { commit.hasSuffix("-dirty") }

    var commitURL: URL {
        let sha = commit.replacingOccurrences(of: "-dirty", with: "")
        return URL(string: "https://github.com/\(GitHubFeedback.owner)/\(GitHubFeedback.repo)/commit/\(sha)")!
    }

    var summary: String {
        "MD Reader \(version) (\(build)) · \(commit) on \(branch) · built \(buildDate) · \(commitURL.absoluteString)"
    }
}
