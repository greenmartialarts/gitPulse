# GitPulse 1.0.0

GitPulse 1.0.0 is the first release: a native macOS menu-bar sentinel for pull requests, build health, and local Git hygiene.

## What’s included

- GitHub review queue and authored PR status through GraphQL.
- GitLab.com and self-hosted GitLab merge-request monitoring.
- Native CI failure alerts with deep links to the relevant pull request.
- Menu-bar status indicators for all-clear, review-needed, failing, and disconnected states.
- Keychain-backed personal access tokens.
- Adaptive polling for low background impact.
- Local repository discovery, dirty-state inspection, stash creation, and merged-branch cleanup.
- A settings window that always comes to the front from the menu bar.
- Universal binaries for both Apple Silicon and Intel Macs (macOS 13+).

## Install

Download `GitPulse-universal.zip`, unzip it, and move `GitPulse.app` to Applications. On first launch, open the menu-bar icon and choose **Settings…** to add a personal access token.

