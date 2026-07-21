import SwiftUI
import AppKit
import UserNotifications

struct PulsePopover: View {
    @ObservedObject var model: PulseModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: model.menuSymbol).symbolRenderingMode(.hierarchical).foregroundStyle(color); VStack(alignment: .leading) { Text(statusTitle).font(.headline); Text(statusSubtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel("Refresh GitPulse") }
                .padding()
            Divider()
            if model.preferences.githubToken.isEmpty { VStack(spacing: 8) { Image(systemName: "key.horizontal").font(.title); Text("Connect GitHub").font(.headline); Text("Add a personal access token in Settings to start monitoring.").font(.caption).foregroundStyle(.secondary) }.frame(height: 180) }
            else { List { Section("Review requests") { if model.reviewQueue.isEmpty { Text("Nothing needs your review").foregroundStyle(.secondary) } else { ForEach(model.reviewQueue) { PRRow(pr: $0) } } }; Section("Your pull requests") { if model.authoredPRs.isEmpty { Text("No open pull requests").foregroundStyle(.secondary) } else { ForEach(model.authoredPRs) { PRRow(pr: $0) } } } }.listStyle(.inset)
                .frame(height: 320) }
            Divider(); HStack { Button("Open GitPulse") { WindowFocus.open(id: "dashboard", title: "GitPulse", using: openWindow) }; Button("Settings…") { WindowFocus.open(id: "settings", title: "GitPulse Settings", using: openWindow) }; Spacer(); Button("Quit") { NSApplication.shared.terminate(nil) } }.padding(12)
        }.frame(width: 390).task { await NotificationPermissions.request() }
    }
    private var color: Color { switch model.health { case .healthy: .green; case .review: .yellow; case .failing: .red; case .unknown: .secondary } }
    private var statusTitle: String { switch model.health { case .healthy: "All clear"; case .review: "Reviews waiting"; case .failing: "Build needs attention"; case .unknown: "Not connected" } }
    private var statusSubtitle: String { model.lastRefresh.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Checking status" }
}

struct PRRow: View { let pr: PullRequest
    var body: some View { Button { NSWorkspace.shared.open(pr.url) } label: { HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(tint).frame(width: 18); VStack(alignment: .leading, spacing: 3) { Text(pr.title).lineLimit(2).foregroundStyle(.primary); Text("\(pr.repository) · \(pr.approvals) reviews").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.forward.square").foregroundStyle(.tertiary) } }.buttonStyle(.plain).accessibilityLabel("Open pull request \(pr.title)") }
    var icon: String { switch pr.checks { case .passed: "checkmark.circle.fill"; case .running: "arrow.triangle.2.circlepath.circle.fill"; case .failed: "xmark.circle.fill"; case .pending: "clock.fill" } }
    var tint: Color { pr.checks == .failed ? .red : pr.checks == .passed ? .green : .orange }
}

struct DashboardView: View { @ObservedObject var model: PulseModel
    var body: some View { NavigationSplitView { List { NavigationLink("Review Queue", destination: PRList(title: "Review Queue", prs: model.reviewQueue)); NavigationLink("Authored Pull Requests", destination: PRList(title: "Your Pull Requests", prs: model.authoredPRs)); NavigationLink("Local Repositories", destination: RepositoryList(model: model)) }.navigationTitle("GitPulse") } detail: { VStack(spacing: 16) { Image(systemName: model.menuSymbol).font(.system(size: 48)).foregroundStyle(model.health == .failing ? .red : Color.accentColor); Text("GitPulse Sentinel").font(.title2); Text("Choose a queue or local repository from the sidebar.").foregroundStyle(.secondary); Button("Refresh now") { Task { await model.refresh() } } }.frame(maxWidth: .infinity, maxHeight: .infinity) }.toolbar { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
}

struct PRList: View { let title: String; let prs: [PullRequest]; var body: some View { List { if prs.isEmpty { Label("No pull requests", systemImage: "arrow.triangle.pull").foregroundStyle(.secondary) } else { ForEach(prs) { PRRow(pr: $0) } } }.navigationTitle(title) } }

struct RepositoryList: View {
    @ObservedObject var model: PulseModel
    var body: some View { List { ForEach(model.repositories) { repo in
        Section(repo.path) { Label(repo.branch.isEmpty ? "Not a git repository" : repo.branch, systemImage: "arrow.triangle.branch")
            if !repo.dirtyFiles.isEmpty { Text("\(repo.dirtyFiles.count) changed files").foregroundStyle(.orange); Button("Stash all changes") { model.stash(repo) } }
            if !repo.stashes.isEmpty { DisclosureGroup("\(repo.stashes.count) stash entries") { ForEach(repo.stashes, id: \.self) { Text($0).font(.caption.monospaced()) } } }
            if !repo.mergedBranches.isEmpty { DisclosureGroup("Merged branches") { ForEach(repo.mergedBranches, id: \.self) { branch in HStack { Text(branch).font(.caption.monospaced()); Spacer(); Button("Delete", role: .destructive) { model.deleteBranch(branch, repo: repo) } } } } }
        }
    } }.navigationTitle("Local Repositories") }
}

struct SettingsView: View {
    @ObservedObject var model: PulseModel; @State private var showingFolder = false
    var body: some View { Form { Section("Accounts") { SecureField("GitHub token", text: $model.preferences.githubToken); TextField("GitLab host", text: $model.preferences.gitlabHost); SecureField("GitLab token", text: $model.preferences.gitlabToken) }; Section("Polling") { Toggle("Monitor automatically", isOn: $model.preferences.pollingEnabled) }; Section("Watched folders") { ForEach(model.preferences.repositories, id: \.self) { Text($0).font(.caption.monospaced()) }; Button("Add repository…") { showingFolder = true }; Button { model.discoverRepositories() } label: { if model.isDiscovering { ProgressView().controlSize(.small); Text("Scanning accessible disks…") } else { Label("Find repositories on this Mac", systemImage: "magnifyingglass") } }.disabled(model.isDiscovering); Text("Scans your home folder, iCloud Drive, and mounted volumes. Grant Full Disk Access in System Settings to include protected folders.").font(.caption).foregroundStyle(.secondary) } }.padding().onChange(of: model.preferences.pollingEnabled) { _ in model.save(); model.startPolling() }.onChange(of: model.preferences.githubToken) { _ in model.save() }.onChange(of: model.preferences.gitlabToken) { _ in model.save() }.onChange(of: model.preferences.gitlabHost) { _ in model.save() }.fileImporter(isPresented: $showingFolder, allowedContentTypes: [.folder]) { result in if case .success(let url) = result { model.addRepository(url.path) } } }
}

enum NotificationPermissions { static func request() async { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }

@MainActor
enum WindowFocus {
    static func open(id: String, title: String, using openWindow: OpenWindowAction) {
        openWindow(id: id)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title == title }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
