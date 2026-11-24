# OrbitHUD Package Manager Distribution Guide

This folder contains the package manifests for **Homebrew Cask (macOS)**, **WinGet (Windows)**, and **AUR (Arch Linux)**, paired with `.github/workflows/publish-packages.yml` for automated updates on every GitHub Release.

---

## One-Time Maintainer Setup

### 1. Homebrew Cask (macOS)
1. Create a public GitHub repository named `mojtaba-afraz/homebrew-tap`.
2. Copy `packaging/homebrew/orbithud.rb` to `Casks/orbithud.rb` in that repo.
3. Create a GitHub Personal Access Token (PAT) with `Contents: Read and write` permission on `homebrew-tap`.
4. Add it to **OrbitHUD** → Settings → Secrets → Actions as `HOMEBREW_TAP_GITHUB_TOKEN`.

Users can then install and update via:
```bash
brew tap mojtaba-afraz/tap
brew install --cask orbithud
```

### 2. WinGet (Windows)
1. Fork `microsoft/winget-pkgs` to your GitHub account.
2. Submit the initial version once by copying `packaging/winget/*.yaml` (with the real `InstallerSha256` from `SHA256SUMS.txt` on the latest release) into `manifests/m/MojtabaAfraz/OrbitHUD/<version>/` and opening a PR to `microsoft/winget-pkgs`.
3. Create a classic PAT with `public_repo` scope and add it to **OrbitHUD** Secrets as `WINGET_PAT`.
4. All future releases are automatically submitted via `vedantmgoyal9/winget-releaser`.

Users can then install via:
```powershell
winget install MojtabaAfraz.OrbitHUD
```

### 3. Arch User Repository — AUR (Arch Linux)
1. Register an SSH key on https://aur.archlinux.org and create the `orbithud-bin` package repo.
2. Add the matching SSH private key to **OrbitHUD** Secrets as `AUR_SSH_PRIVATE_KEY`.
3. On every release, `publish-packages.yml` updates `pkgver` and `sha256sums_x86_64`, validates the package, and pushes to AUR automatically.

Users can then install via:
```bash
yay -S orbithud-bin
```
