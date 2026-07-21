# Changelog

All notable changes to GitPulse are documented here.

## 1.0.2 — 2026-07-21

### Fixed

- Removed Swift 6-only notification and task-capture syntax so universal builds work on GitHub's Swift 5.10 macOS runners.

## 1.0.1 — 2026-07-21

### Fixed

- Made the Swift package manifest compatible with the Swift 5.10 toolchain on GitHub's Intel macOS runner, restoring universal-release builds.

## 1.0.0 — 2026-07-21

### Added

- Native macOS menu-bar sentinel for GitHub and GitLab pull/merge requests.
- GitHub GraphQL review queue and authored pull-request tracking.
- GitLab.com and self-hosted GitLab merge-request polling.
- Global menu-bar health states for healthy, review-needed, failing, and disconnected states.
- Native build-failure notifications that open the relevant pull request.
- Secure GitHub and GitLab PAT storage in the macOS Keychain.
- Adaptive polling: one minute while active and five minutes when idle or in Low Power Mode.
- Repository inspection for active branch, dirty files, stashes, and merged local branches.
- One-click stash creation and safe deletion of merged local branches.
- Repository discovery across the user home directory, iCloud Drive, and mounted volumes.
- Dedicated settings window that is brought to the foreground from the menu-bar popover.
- Universal macOS app packaging for Apple Silicon and Intel Macs.
