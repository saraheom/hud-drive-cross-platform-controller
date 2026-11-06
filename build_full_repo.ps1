# HUD Controller v90.35.3.24.35 complete source builder.
# Requires Git, Python 3, Windows PowerShell 5.1+ or PowerShell 7.
param(
  [string]$ExistingRepo = '',
  [switch]$NoZip,
  [switch]$CommitLocally
)
$ErrorActionPreference = 'Stop'
$base = '197741e9aaaf19d895a2994091e3971d665ff992'
$branch = 'fix/2026-11-05-auto-map-mode-hud-rejoin'
$pkg = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = ''

if ($ExistingRepo -ne '') {
  $repo = (Resolve-Path -LiteralPath $ExistingRepo).Path
  $head = (& git -C $repo rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw "Not a Git checkout: $repo" }
  if ($head -ne $base) { throw "Repository HEAD $head does not match reviewed base $base. No changes made. Use fresh clone or inspect history." }
} else {
  $repo = Join-Path $pkg 'hud-drive-cross-platform-controller'
  if (Test-Path -LiteralPath $repo) { throw "Existing directory: $repo. Delete/rename it or use -ExistingRepo." }
  & git clone https://github.com/saraheom/hud-drive-cross-platform-controller.git $repo
  if ($LASTEXITCODE -ne 0) { throw 'Git clone failed. Verify network and Git access.' }
  & git -C $repo checkout --detach $base
  if ($LASTEXITCODE -ne 0) { throw 'Reviewed base commit is missing from clone.' }
}

$changes = & git -C $repo status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Working tree has uncommitted files. Commit or stash first.' }
& git -C $repo switch -c $branch
if ($LASTEXITCODE -ne 0) { throw "Cannot create branch $branch (might already exist)." }

$python = Get-Command python -ErrorAction SilentlyContinue
$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($python) {
  & python (Join-Path $pkg 'apply_to_repo.py') $repo
} elseif ($pyLauncher) {
  & py -3 (Join-Path $pkg 'apply_to_repo.py') $repo
} else {
  throw 'Python 3 required. Install Python 3 and rerun with -ExistingRepo after resetting partial checkout.'
}
if ($LASTEXITCODE -ne 0) { throw 'Source patch failed. Do not commit. Inspect errors above.' }

Write-Host "Source patched at: $repo"
& git -C $repo status --short
& git -C $repo diff --check
if ($LASTEXITCODE -ne 0) { throw 'Whitespace/error check failed.' }

if ($CommitLocally) {
  & git -C $repo add ios/HUDController/App/AppState.swift ios/HUDController/App/HUDMapModeAutoRejoinPolicy.swift ios/HUDControllerTests/V90352435AutoMapRejoinTests.swift
  & git -C $repo commit -m 'Recover HUD Map Mode viewer after physical restarts without restarting MainVideo'
  if ($LASTEXITCODE -ne 0) { throw 'Commit failed. No remote push performed.' }
}

if (-not $NoZip) {
  $dest = Join-Path $pkg 'HUD_Controller_v90.35.3.24.35_FULL_SOURCE.zip'
  if (Test-Path $dest) { Remove-Item $dest -Force }
  $staging = Join-Path $pkg '.full_source_staging'
  if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
  New-Item -ItemType Directory -Path $staging | Out-Null
  $stagingRepo = Join-Path $staging 'hud-drive-cross-platform-controller'
  New-Item -ItemType Directory -Path $stagingRepo | Out-Null
  Get-ChildItem -LiteralPath $repo -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stagingRepo -Recurse -Force
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $dest, [System.IO.Compression.CompressionLevel]::Optimal, $false)
  Remove-Item $staging -Recurse -Force
  Write-Host "FULL SOURCE ZIP CREATED: $dest"
}

Write-Host 'CI still needs to run on macOS after pushing. No adapter firmware changes.'
Write-Host 'To publish: git -C "' $repo '" push -u origin ' $branch
Write-Host 'To open PR: https://github.com/saraheom/hud-drive-cross-platform-controller/compare/main...fix/2026-11-05-auto-map-mode-hud-rejoin'
