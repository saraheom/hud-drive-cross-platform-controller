param(
    [string]$WorkDir = (Join-Path $PSScriptRoot 'build-output'),
    [switch]$Push
)
$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/saraheom/hud-drive-cross-platform-controller.git'
$baseSHA = '70591ca535f0d8fd6e42aa2f6e83a46f339cfd8c'
$branch = 'fix/nov15-v2436-spotlight-ci-integration'
$sourceDir = Join-Path $WorkDir 'hud-drive-cross-platform-controller'
$outputZIP = Join-Path $WorkDir 'HUD_Controller_v90_35_3_24_36_CI_FIXED_FULL_SOURCE.zip'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows required.' }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
if (Test-Path $sourceDir) { throw "Directory exists: $sourceDir. Use a clean -WorkDir." }
& git clone $repoUrl $sourceDir
if ($LASTEXITCODE -ne 0) { throw 'Git clone failed.' }
Push-Location $sourceDir
try {
    & git checkout --detach $baseSHA
    if ($LASTEXITCODE -ne 0) { throw 'The pinned CI-failing source revision is not in your checkout.' }
    & git switch -c $branch
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create feature branch.' }
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'apply_ci_fix.ps1') -RepoPath $sourceDir
    if ($LASTEXITCODE -ne 0) { throw 'Patch failed validation.' }
    & git add -- ios/HUDController/Models/HudMapModeSettings.swift ios/HUDController/MapMode/HudMapModeCanvas.swift ios/HUDController/MapMode/U2WMainVideoClient.swift
    & git commit -m 'Fix incomplete v24.36 Route Spotlight and decoder recovery integration'
    if ($LASTEXITCODE -ne 0) { throw 'Commit failed. Configure git user.name/email if needed.' }
    & git archive --format=zip --output=$outputZIP HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Full-source ZIP creation failed.' }
    Write-Host "FULL SOURCE ZIP READY: $outputZIP" -ForegroundColor Green
    if ($Push) {
        & git push -u origin $branch
        if ($LASTEXITCODE -ne 0) { throw 'Push failed. Local ZIP and commit remain available.' }
        Write-Host "Pushed $branch. Open a PR into main and run iOS CI on that branch." -ForegroundColor Green
    } else {
        Write-Host 'Feature branch and full-source ZIP created locally. Use -Push to publish the branch.'
    }
} finally { Pop-Location }
