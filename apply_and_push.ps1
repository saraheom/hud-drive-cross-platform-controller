param(
    [Parameter(Mandatory=$true)][string]$RepoPath,
    [switch]$Push
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Repo = (Resolve-Path -LiteralPath $RepoPath).Path
$Expected = "ae68a85c2ca15c1bcce484e88b0a4f5546c14866"
$ChangePaths = @(
    "ios/HUDControllerTests/V90352429StartupBootstrapFullCanvasTests.swift",
    "ios/HUDControllerTests/V90352431ResourceSafeBackgroundProbeTests.swift",
    "ios/HUDControllerTests/V90352432ProductionMapBackgroundETAWarningTests.swift",
    ".github/workflows/ios-ci.yml"
)

$Branch = (& git -C $Repo branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $Branch -ne "main") {
    throw "Expected local main branch, found '$Branch'."
}
$Changes = & git -C $Repo status --porcelain
if ($LASTEXITCODE -ne 0 -or $Changes) {
    throw "Working tree is not clean. Commit/stash your existing changes first."
}
$Origin = (& git -C $Repo remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or $Origin -notmatch '(^|[:/])saraheom/hud-drive-cross-platform-controller(\.git)?$') {
    throw "Git origin does not match the reviewed HUD Controller repository: $Origin"
}

Write-Host "Fetching latest origin/main ..."
& git -C $Repo fetch origin main
if ($LASTEXITCODE -ne 0) { throw "Could not fetch origin/main." }
& git -C $Repo merge --ff-only origin/main
if ($LASTEXITCODE -ne 0) { throw "Could not fast-forward to origin/main." }
$Head = (& git -C $Repo rev-parse HEAD).Trim()
if ($Head -ne $Expected) {
    throw "Repository has advanced: expected $Expected, found $Head. Refusing a stale patch."
}

Write-Host "Applying regression-contract updates to actual Swift XCTest files and CI workflow ..."
& python (Join-Path $PSScriptRoot "apply_test_contract_fix.py") --repo $Repo
if ($LASTEXITCODE -ne 0) { throw "Patch/validation failed; no commit was made." }

& git -C $Repo diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed; no commit." }
$Changed = @(& git -C $Repo diff --name-only)
if ($LASTEXITCODE -ne 0) { throw "Could not verify changed source files." }
foreach ($p in $ChangePaths) {
    if ($Changed -notcontains $p) { throw "Expected changed source file missing: $p" }
}
if ($Changed.Count -ne $ChangePaths.Count) {
    throw "Unexpected changes: $($Changed -join ', ')"
}

Write-Host "Committing FOUR actual repository files (not the installer) ..."
& git -C $Repo add -- $ChangePaths
if ($LASTEXITCODE -ne 0) { throw "git add failed" }
& git -C $Repo diff --cached --check
if ($LASTEXITCODE -ne 0) { throw "staged changes invalid" }
& git -C $Repo commit -m "Fix v24.36 CI source contracts and auto-run CI on every push"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }

if ($Push) {
    Write-Host "Pushing main. The updated iOS CI should start for ANY branch push ..."
    & git -C $Repo push origin main
    if ($LASTEXITCODE -ne 0) { throw "Push failed; local commit still exists. Retry: git push origin main" }
    Write-Host "Push succeeded. Check: https://github.com/saraheom/hud-drive-cross-platform-controller/actions/workflows/ios-ci.yml"
} else {
    Write-Host "Commit created locally. To trigger iOS CI, run: git push origin main"
}
