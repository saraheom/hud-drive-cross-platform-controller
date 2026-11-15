param(
    [string]$WorkDir = (Join-Path $PSScriptRoot 'build-output'),
    [switch]$Push
)
$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/saraheom/hud-drive-cross-platform-controller.git'
$baseSHA = '4f7e2c030d8aacf5565ef81286ed52c8a363c439'
$branch = 'fix/nov15-video-route-spotlight'
$sourceDir = Join-Path $WorkDir 'hud-drive-cross-platform-controller'
$outputZIP = Join-Path $WorkDir 'HUD_Controller_v90_35_3_24_36_FULL_SOURCE.zip'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required. Install Git for Windows first.' }
$python = Get-Command py -ErrorAction SilentlyContinue
if ($python) { $pythonCommand = 'py'; $pythonArgs = @('-3') }
elseif (Get-Command python -ErrorAction SilentlyContinue) { $pythonCommand = 'python'; $pythonArgs = @() }
else { throw 'Python 3 is required to apply and validate the source patch.' }

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
if (Test-Path $sourceDir) { throw "Output checkout already exists: $sourceDir. Use a clean WorkDir to avoid overwriting work." }
Write-Host 'Cloning the reviewed HUD Controller repository...' -ForegroundColor Cyan
& git clone $repoUrl $sourceDir
if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
Push-Location $sourceDir
try {
    & git checkout --detach $baseSHA
    if ($LASTEXITCODE -ne 0) { throw "Cannot find pinned source commit $baseSHA" }
    & git switch -c $branch
    if ($LASTEXITCODE -ne 0) { throw "Cannot create $branch" }
    & $pythonCommand @pythonArgs (Join-Path $PSScriptRoot 'apply_to_repo.py') --repo $sourceDir
    if ($LASTEXITCODE -ne 0) { throw 'Patch failed: source did not match reviewed base revision.' }
    & git add -- ios/HUDController/MapMode/HudRouteSpotlightProcessor.swift ios/HUDController/MapMode/HudMapModeCanvas.swift ios/HUDController/Models/HudMapModeSettings.swift ios/HUDController/MapMode/U2WMainVideoClient.swift ios/HUDControllerTests/V90352436RouteSpotlightAndRecoveryTests.swift
    & git commit -m 'v90.35.3.24.36: preserve TCP for codec recovery and add experimental Route Spotlight filter'
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed (configure Git user.name/email if required).' }
    & git archive --format=zip --output=$outputZIP HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
    Write-Host "FULL REPO READY: $outputZIP" -ForegroundColor Green
    Write-Host "Local branch: $branch"
    if ($Push) {
        & git push -u origin $branch
        if ($LASTEXITCODE -ne 0) { throw 'git push failed; the local checkout and ZIP remain available.' }
        Write-Host "Pushed branch: $branch. Open a PR against main and run iOS CI." -ForegroundColor Green
    } else {
        Write-Host 'The branch is local. Use -Push to push it, then run iOS CI on GitHub.'
    }
} finally { Pop-Location }
