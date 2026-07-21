import Foundation
import Observation
import Combine

enum Health: String, Codable { case healthy, review, failing, unknown
    var symbol: String { switch self { case .healthy: "checkmark.circle.fill"; case .review: "eye.circle.fill"; case .failing: "exclamationmark.triangle.fill"; case .unknown: "circle.dashed" } }
}

struct PullRequest: Identifiable, Codable, Hashable {
    var id: String; var title: String; var repository: String; var author: String; var url: URL
    var reviewRequested: Bool; var checks: CheckState; var approvals: Int
}
enum CheckState: String, Codable { case passed, running, failed, pending }
struct LocalRepository: Identifiable, Codable, Hashable { var id: UUID = UUID(); var path: String; var branch: String = ""; var dirtyFiles: [String] = []; var stashes: [String] = []; var mergedBranches: [String] = [] }
struct AppPreferences: Codable { var githubToken: String = ""; var gitlabToken: String = ""; var gitlabHost = "https://gitlab.com"; var repositories: [String] = []; var pollingEnabled = true }

@MainActor final class PulseModel: ObservableObject {
    @Published var preferences = AppPreferences()
    @Published var reviewQueue: [PullRequest] = []
    @Published var authoredPRs: [PullRequest] = []
    @Published var repositories: [LocalRepository] = []
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var isDiscovering = false
    private var timer: Timer?
    private var lastFailed: Set<String> = []

    init() { load(); startPolling(); Task { await refresh() } }
    var health: Health {
        if reviewQueue.contains(where: { $0.checks == .failed }) || authoredPRs.contains(where: { $0.checks == .failed }) { return .failing }
        if !reviewQueue.isEmpty { return .review }
        return preferences.githubToken.isEmpty && preferences.gitlabToken.isEmpty ? .unknown : .healthy
    }
    var menuSymbol: String { health.symbol }
    func save() { Keychain.save(preferences.githubToken, account: "github-token"); Keychain.save(preferences.gitlabToken, account: "gitlab-token"); var persisted = preferences; persisted.githubToken = ""; persisted.gitlabToken = ""; UserDefaults.standard.set(try? JSONEncoder().encode(persisted), forKey: "preferences") }
    func load() { if let d = UserDefaults.standard.data(forKey: "preferences"), let p = try? JSONDecoder().decode(AppPreferences.self, from: d) { preferences = p }; preferences.githubToken = Keychain.read(account: "github-token") ?? ""; preferences.gitlabToken = Keychain.read(account: "gitlab-token") ?? ""; repositories = preferences.repositories.map { LocalRepository(path: $0) }; Task { await refreshRepos() } }
    func startPolling() { timer?.invalidate(); guard preferences.pollingEnabled else { return }; timer = Timer.scheduledTimer(withTimeInterval: Polling.interval, repeats: true) { [weak self] _ in guard let model = self else { return }; Task { @MainActor in await model.refresh(); model.startPolling() } } }
    func refresh() async { guard !isRefreshing else { return }; isRefreshing = true; defer { isRefreshing = false; lastRefresh = .now }; errorMessage = nil
        await refreshRepos()
        var reviews: [PullRequest] = []; var authored: [PullRequest] = []
        if !preferences.githubToken.isEmpty { do { let result = try await GitHubClient(token: preferences.githubToken).fetch(); reviews += result.reviews; authored += result.authored } catch { errorMessage = error.localizedDescription } }
        if !preferences.gitlabToken.isEmpty { do { let result = try await GitLabClient(token: preferences.gitlabToken, host: preferences.gitlabHost).fetch(); reviews += result.reviews; authored += result.authored } catch { errorMessage = error.localizedDescription } }
        reviewQueue = reviews; authoredPRs = authored; notifyNewFailures(reviews + authored)
    }
    func refreshRepos() async { let paths = preferences.repositories; repositories = await Task.detached { paths.map { GitEngine.inspect($0) } }.value }
    func addRepository(_ path: String) { guard !preferences.repositories.contains(path) else { return }; preferences.repositories.append(path); save(); Task { await refreshRepos() } }
    func discoverRepositories() {
        guard !isDiscovering else { return }; isDiscovering = true
        let existing = Set(preferences.repositories)
        Task { @MainActor in
            let found = await Task.detached { RepositoryDiscovery.scan() }.value
            for path in found where !existing.contains(path) { preferences.repositories.append(path) }
            save(); await refreshRepos(); isDiscovering = false
        }
    }
    func stash(_ repo: LocalRepository) { GitEngine.run(["stash", "push", "-u", "-m", "GitPulse quick stash"], at: repo.path); Task { await refreshRepos() } }
    func deleteBranch(_ branch: String, repo: LocalRepository) { GitEngine.run(["branch", "-d", branch], at: repo.path); Task { await refreshRepos() } }
    private func notifyNewFailures(_ prs: [PullRequest]) { let failures = Set(prs.filter { $0.checks == .failed }.map(\.id)); for pr in failures.subtracting(lastFailed) { if let item = prs.first(where: { $0.id == pr }) { Notifier.failure(item) } }; lastFailed = failures }
}
