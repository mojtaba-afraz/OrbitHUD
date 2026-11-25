# OrbitHUD Roadmap

This document outlines the planned development roadmap for **OrbitHUD** across both the native **macOS (Swift/SwiftUI)** app and the **Windows/Linux (Electron)** app.

Every upcoming feature is tracked as an open [GitHub Issue](https://github.com/mojtaba-afraz/OrbitHUD/issues) and organized into [Milestones](https://github.com/mojtaba-afraz/OrbitHUD/milestones). Community contributions, feedback, and PRs are always welcome!

---

## ✅ Recently Shipped (`v1.2.2`)

- **Core reliability & UX fixes:** Fixed `TokenFormatter` K-unit scaling, added multi-monitor screen bounds validation so the widget never gets lost off-screen, and added **Launch at Login** support.
- **Security & CI:** Added SHA256 verification to the Electron auto-updater, expanded unit test coverage, and added automated CI test runs.

---

## 🎯 [v1.3.0 — Platform Parity & Smart Alerts](https://github.com/mojtaba-afraz/OrbitHUD/milestone/1)

Focus: Full parity between native macOS and Windows/Linux, plus proactive alerts and faster keyboard-driven workflows.

| Status | Feature | Platforms | Issue |
| :---: | :--- | :--- | :---: |
| ⬜ | **Native macOS Auto-Updater** via GitHub Releases with SHA256 verification | macOS | [#1](https://github.com/mojtaba-afraz/OrbitHUD/issues/1) |
| ⬜ | **Refresh Interval control in Settings UI** (`15s`, `30s`, `60s`, `2m`, `5m`) | macOS, Win/Linux | [#2](https://github.com/mojtaba-afraz/OrbitHUD/issues/2) |
| ⬜ | **Configurable Primary Quota Model** in Menu Bar & System Tray (Auto Lowest or Pinned Model) | macOS, Win/Linux | [#3](https://github.com/mojtaba-afraz/OrbitHUD/issues/3) |
| ⬜ | **Smart Quota Alerts & Reset Notifications** (low-quota threshold & 5h window reset alerts) | macOS, Win/Linux | [#4](https://github.com/mojtaba-afraz/OrbitHUD/issues/4) |
| ⬜ | **Global Hotkey** to toggle HUD visibility & Bento/Compact Pill layout | macOS, Win/Linux | [#5](https://github.com/mojtaba-afraz/OrbitHUD/issues/5) |

---

## 📊 [v1.4.0 — Analytics, Themes & Multi-Provider Ecosystem](https://github.com/mojtaba-afraz/OrbitHUD/milestone/2)

Focus: Deeper usage insights, visual customization, and broader opt-in AI coding tool support.

| Status | Feature | Platforms | Issue |
| :---: | :--- | :--- | :---: |
| ⬜ | **Burn Rate, Time-to-Depletion & 7-Day Token Analytics Drawer** | macOS, Win/Linux | [#6](https://github.com/mojtaba-afraz/OrbitHUD/issues/6) |
| ⬜ | **Expand Opt-in Multi-Provider Support** (Cursor, GitHub Copilot, OpenRouter / Gemini API) | macOS, Win/Linux | [#7](https://github.com/mojtaba-afraz/OrbitHUD/issues/7) |
| ⬜ | **Glassmorphic Themes & Auto Light/Dark Adaptation** (Obsidian, Frost, Midnight, Auto) | macOS, Win/Linux | [#8](https://github.com/mojtaba-afraz/OrbitHUD/issues/8) |

---

## 🚀 [v2.0.0 — Native WidgetKit & Multi-Arch](https://github.com/mojtaba-afraz/OrbitHUD/milestone/3)

Focus: Deep OS integration and full ARM64 distribution.

| Status | Feature | Platforms | Issue |
| :---: | :--- | :--- | :---: |
| ⬜ | **Native macOS WidgetKit Extension** for Sonoma+ Desktop & Notification Center | macOS | [#9](https://github.com/mojtaba-afraz/OrbitHUD/issues/9) |
| ⬜ | **Windows ARM64 & Linux ARM64 Release Builds** in CI/CD & Auto-Updater | Win/Linux | [#10](https://github.com/mojtaba-afraz/OrbitHUD/issues/10) |

---

## 🤝 Contributing

Want to help build one of these features?

1. Browse issues labeled [`good first issue`](https://github.com/mojtaba-afraz/OrbitHUD/labels/good%20first%20issue) or [`help wanted`](https://github.com/mojtaba-afraz/OrbitHUD/labels/help%20wanted).
2. Comment on the issue you'd like to work on so we can coordinate and avoid duplicate effort.
3. Follow OrbitHUD's core principles:
   - **Privacy-first & zero telemetry:** External providers must always be opt-in and disabled by default.
   - **Platform parity where possible:** Keep macOS (`Sources/`) and cross-platform (`cross-platform/`) behavior aligned.
   - **Test coverage:** Add unit tests in `Tests/AntigravityUsageCoreTests/` and/or `cross-platform/tests/`.
4. Open a Pull Request referencing the issue (e.g. `Closes #2`).
