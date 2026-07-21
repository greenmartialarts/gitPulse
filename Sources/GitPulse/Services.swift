import Foundation
import Security
import UserNotifications
import ApplicationServices

enum Keychain {
    static func save(_ value: String, account: String) { guard !value.isEmpty else { return }; let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.gitpulse.app", kSecAttrAccount as String: account]; SecItemDelete(query as CFDictionary); var add = query; add[kSecValueData as String] = value.data(using: .utf8); SecItemAdd(add as CFDictionary, nil) }
    static func read(account: String) -> String? { let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.gitpulse.app", kSecAttrAccount as String: account, kSecReturnData as String: true]; var item: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }; return String(data: data, encoding: .utf8) }
}

enum GitEngine {
    static func run(_ args: [String], at path: String) { _ = output(args, at: path) }
    static func output(_ args: [String], at path: String) -> String { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = args; p.currentDirectoryURL = URL(fileURLWithPath: path); let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe(); do { try p.run(); p.waitUntilExit(); return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" } catch { return "" } }
    static func inspect(_ path: String) -> LocalRepository { let branch = output(["branch", "--show-current"], at: path).trimmingCharacters(in: .whitespacesAndNewlines); let files = output(["status", "--porcelain"], at: path).split(separator: "\n").map(String.init); let stashes = output(["stash", "list", "--format=%gd: %s"], at: path).split(separator: "\n").map(String.init); let merged = output(["branch", "--merged", "@{upstream}"], at: path).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }.filter { !$0.isEmpty && $0 != branch }; return LocalRepository(path: path, branch: branch, dirtyFiles: files, stashes: stashes, mergedBranches: merged) }
}

enum RepositoryDiscovery {
    /// Scans locations macOS makes visible to the app, including user home, iCloud Drive and mounted volumes.
    static func scan() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var roots = [home, URL(fileURLWithPath: "/Volumes", isDirectory: true)]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fm.fileExists(atPath: iCloud.path) { roots.append(iCloud) }
        var found = Set<String>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isReadableKey]
        let ignored: Set<String> = [".git", "node_modules", "DerivedData", ".build", "Pods", "Library", ".Trash", ".cache"]
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants, .skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if ignored.contains(name) { enumerator.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: Set(keys)).isDirectory) == true else { continue }
                if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { found.insert(url.path); enumerator.skipDescendants() }
            }
        }
        return found.sorted()
    }
}

enum Notifier { static func failure(_ pr: PullRequest) { let c = UNMutableNotificationContent(); c.title = "Build failed"; c.body = "\(pr.repository): \(pr.title)"; c.sound = .default; c.userInfo = ["url": pr.url.absoluteString]; let r = UNNotificationRequest(identifier: "failure-\(pr.id)", content: c, trigger: nil); UNUserNotificationCenter.current().add(r) } }
enum Polling { static var interval: TimeInterval { ProcessInfo.processInfo.isLowPowerModeEnabled || CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null) > 300 ? 300 : 60 } }

struct GitHubClient {
    let token: String
    struct Result { let reviews: [PullRequest]; let authored: [PullRequest] }
    func fetch() async throws -> Result {
        let query = "query { viewer { login reviewRequests(first: 30) { nodes { pullRequest { id title url author { login } repository { nameWithOwner } reviews(first: 30) { totalCount } commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } pullRequests(first: 30, states: OPEN) { nodes { id title url author { login } repository { nameWithOwner } reviews(first: 30) { totalCount } commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }"
        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!); req.httpMethod = "POST"; req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query]); let (data, response) = try await URLSession.shared.data(for: req); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }; return try decode(data)
    }
    private func decode(_ data: Data) throws -> Result { let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]; let viewer = ((root["data"] as? [String: Any])?["viewer"] as? [String: Any]) ?? [:]; let login = viewer["login"] as? String ?? ""; func map(_ raw: [[String: Any]], review: Bool) -> [PullRequest] { raw.compactMap { node in let p = (node["pullRequest"] as? [String: Any]) ?? node; guard let id = p["id"] as? String, let title = p["title"] as? String, let urlString = p["url"] as? String, let url = URL(string: urlString) else { return nil }; let repo = (p["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? "Unknown"; let author = (p["author"] as? [String: Any])?["login"] as? String ?? ""; let approvals = ((p["reviews"] as? [String: Any])?["totalCount"] as? Int) ?? 0; let state = ((((p["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])?["state"] as? String ?? "PENDING"; let check: CheckState = state == "SUCCESS" ? .passed : state == "FAILURE" || state == "ERROR" ? .failed : state == "PENDING" ? .pending : .running; return PullRequest(id: id, title: title, repository: repo, author: author, url: url, reviewRequested: review, checks: check, approvals: approvals) } }; let reviews = (((viewer["reviewRequests"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []); let authored = (((viewer["pullRequests"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).filter { (($0["author"] as? [String: Any])?["login"] as? String) == login }; return Result(reviews: map(reviews, review: true), authored: map(authored, review: false)) }
}

struct GitLabClient {
    let token: String; let host: String
    struct Result { let reviews: [PullRequest]; let authored: [PullRequest] }
    func fetch() async throws -> Result {
        let base = host.trimmingCharacters(in: CharacterSet(charactersIn: "/")); var me = URLRequest(url: URL(string: "\(base)/api/v4/user")!); me.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN"); let (data, _) = try await URLSession.shared.data(for: me); let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]; guard let name = user["username"] as? String else { throw URLError(.userAuthenticationRequired) }
        async let reviews = request("\(base)/api/v4/merge_requests?scope=all&state=opened&reviewer_username=\(name)&per_page=50")
        async let authored = request("\(base)/api/v4/merge_requests?scope=all&state=opened&author_username=\(name)&per_page=50")
        return try await Result(reviews: map(reviews, review: true), authored: map(authored, review: false))
    }
    private func request(_ value: String) async throws -> Data { var request = URLRequest(url: URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)!); request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN"); return try await URLSession.shared.data(for: request).0 }
    private func map(_ data: Data, review: Bool) throws -> [PullRequest] { let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []; return values.compactMap { value in guard let id = value["id"] as? Int, let title = value["title"] as? String, let text = value["web_url"] as? String, let url = URL(string: text) else { return nil }; let pipeline = (value["head_pipeline"] as? [String: Any])?["status"] as? String ?? "pending"; let status: CheckState = pipeline == "success" ? .passed : ["failed", "canceled"].contains(pipeline) ? .failed : pipeline == "running" ? .running : .pending; return PullRequest(id: "gitlab-\(id)", title: title, repository: ((value["references"] as? [String: Any])?["full"] as? String) ?? "GitLab", author: ((value["author"] as? [String: Any])?["username"] as? String) ?? "", url: url, reviewRequested: review, checks: status, approvals: 0) } }
}
