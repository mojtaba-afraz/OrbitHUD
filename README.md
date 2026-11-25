<div align="center">
  <img src="assets/logo.png" alt="OrbitHUD Logo" width="150" height="150" />

  <h1>OrbitHUD</h1>
  <p><strong>Zero-Gravity Glassmorphic AI Usage & Quota HUD for Google Antigravity, Claude Code & Codex CLI</strong></p>

  <p>
    <a href="../../releases/latest"><img src="https://img.shields.io/badge/Download-macOS%20(.dmg%20%2F%20.zip)-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" /></a>
    <a href="../../releases/latest"><img src="https://img.shields.io/badge/Download-Windows%20(.exe)-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Download for Windows" /></a>
    <a href="../../releases/latest"><img src="https://img.shields.io/badge/Download-Linux%20(.AppImage%20%2F%20.deb)-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Download for Linux" /></a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/Release-v1.2.1-38BDF8?style=flat-square" alt="Release v1.2.1" />
    <img src="https://img.shields.io/badge/Providers-Antigravity%20%7C%20Claude%20Code%20%7C%20Codex-E8926B?style=flat-square" alt="Providers" />
    <img src="https://img.shields.io/badge/License-MIT-3DDB94?style=flat-square" alt="MIT License" />
    <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-22D3EE?style=flat-square" alt="Platforms" />
  </p>
</div>

---

<div align="center">
  <img src="assets/orbithud-showcase.png" alt="OrbitHUD Glassmorphism Bento & Compact Pill Showcase" width="100%" />
</div>

---

**OrbitHUD** is a lightweight, real-time **Glassmorphism Desktop & Floating AI Usage HUD** built for **Google Antigravity** (`Antigravity IDE`, `Antigravity 2.0`, & `agy` CLI) with **opt-in Multi-Provider Mode** for **Claude Code** and **OpenAI Codex CLI**. By default, it connects locally to your Antigravity Language Server over loopback (`127.0.0.1`) with zero configuration, zero telemetry, and no API keys required.

---

## 📥 Download & Install (No Build Required)

Download the ready-to-use installer for your operating system from the [**Latest Releases**](../../releases/latest) page:

| Operating System | Direct Download | Installation |
| :--- | :--- | :--- |
| **🍎 macOS** *(Apple Silicon & Intel)* | [**`OrbitHUD-macOS.dmg`**](../../releases/latest/download/OrbitHUD-macOS.dmg) / [**`OrbitHUD-macOS.zip`**](../../releases/latest/download/OrbitHUD-macOS.zip) | Open `.dmg` or extract `.zip`, drag to **Applications**, and launch |
| **🪟 Windows** *(10 / 11 x64)* | [**`OrbitHUD-Windows-Setup.exe`**](../../releases/latest/download/OrbitHUD-Windows-Setup.exe) / [**`Portable.exe`**](../../releases/latest/download/OrbitHUD-Windows-Portable.exe) | Double-click `.exe` to install & launch in System Tray |
| **🐧 Linux** *(Ubuntu / Debian / Arch / Fedora)* | [**`OrbitHUD-Linux-x86_64.AppImage`**](../../releases/latest/download/OrbitHUD-Linux-x86_64.AppImage) / [**`OrbitHUD-Linux-amd64.deb`**](../../releases/latest/download/OrbitHUD-Linux-amd64.deb) | Run `.AppImage` directly or install via `sudo dpkg -i OrbitHUD-Linux-amd64.deb` |

### 📦 Package Managers (Homebrew, WinGet, AUR)

**macOS (Homebrew Cask):**
```bash
brew tap mojtaba-afraz/tap
brew install --cask orbithud
```

**Windows (WinGet):**
```powershell
winget install MojtabaAfraz.OrbitHUD
```

**Arch Linux (AUR):**
```bash
yay -S orbithud-bin
```

### ⚡ One-Command Terminal Install (Optional)

**macOS & Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/mojtaba-afraz/OrbitHUD/main/scripts/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/mojtaba-afraz/OrbitHUD/main/scripts/install.ps1 | iex
```

---

## ✨ Features

- **True Layered Glassmorphism (Bento + Dynamic Pill):**
  - Native behind-window wallpaper blur (`NSVisualEffectView` on macOS, `backdrop-filter` on Windows/Linux) with top-lit specular glass rims and hover-responsive Bento tiles.
  - Switch between **Full Bento Glass View** (auto-sizing to your visible models) and an ultra-sleek **Compact Coding Pill (`52px` tall)** that takes almost zero vertical space while coding.
- **100% Parity with Antigravity Usage Quotas:**
  - **Gemini Models:** Live **5h limit** circular gauge + **Weekly limit** progress bar and reset countdowns (`Resets in 3h 10m`, `6d 1h`).
  - **Claude & GPT Models:** Dedicated **5h limit** circular gauge + **Weekly limit** progress bar and reset countdowns.
  - **Gemini 4 Argon:** Dedicated **Weekly limit** circular gauge, progress bar, and reset countdown.
- **Optional Multi-Provider Mode (Privacy-First):**
  - **Google Antigravity** is enabled by default via 100% local loopback (`127.0.0.1`).
  - Optionally enable **Claude Code** (reads macOS Keychain / `~/.claude/.credentials.json`) and **OpenAI Codex CLI** (reads `~/.codex/auth.json`) from **Settings → Providers** to track all your AI coding quotas inside one unified Glassmorphic HUD with segmented provider filter tabs.
- **Dynamic Models & Hide/Show Controls:**
  - Automatically renders any model pool returned by Google Antigravity, Claude Code, or Codex CLI with dynamic window resizing and per-model Hide/Show toggles.
- **3 Flexible Display Modes:**
  - **Floating HUD (`Float`):** Always-on-top across all workspaces/desktops, draggable from anywhere on the card.
  - **Desktop Widget (`Desktop`):** Pinned directly onto your desktop wallpaper behind normal application windows, with position lock (`Lock Desktop`).
  - **Menu Bar / System Tray Popover:** Live percentage in your top macOS Menu Bar (or Windows/Linux System Tray) that opens the full Glassmorphic Usage Bento view on click.

---

<details>
<summary><strong>🛠 For Developers: Building from Source & Automated Releases</strong></summary>

<br />

All release installers (`.dmg`, `.zip`, `.exe`, `.AppImage`, `.deb`) are automatically built and attached to GitHub Releases by [`.github/workflows/release.yml`](.github/workflows/release.yml) whenever a new version tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`) is pushed.

### Local Build (Contributors)

```bash
# Build native macOS release (.zip / .dmg)
./scripts/package_macos_release.sh

# Build cross-platform packages (Windows / Linux / macOS)
cd cross-platform
npm install
npm run dist:win
npm run dist:linux
```

</details>

---

## 📄 License

Released under the [MIT License](LICENSE).
