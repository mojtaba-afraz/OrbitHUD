$ErrorActionPreference = "Stop"
$Repo = if ($env:ORBITHUD_REPO) { $env:ORBITHUD_REPO } else { "mojtaba-afraz/OrbitHUD" }
$Url = "https://github.com/$Repo/releases/latest/download/OrbitHUD-Windows-Setup.exe"
$InstallerPath = Join-Path $env:TEMP "OrbitHUD-Windows-Setup.exe"

Write-Host "==> Downloading OrbitHUD for Windows..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $Url -OutFile $InstallerPath

Write-Host "==> Launching OrbitHUD Installer..." -ForegroundColor Green
Start-Process -FilePath $InstallerPath
