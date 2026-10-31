# HUD controller patch and full source ZIP builder; requires git and Python 3.
param(
  [string]$ExistingRepo = "",
  [switch]$DoNotZip
)
$ErrorActionPreference = 'Stop'
$branch = 'fix/2026-10-31-map-lock-speed-stability'
$pkg = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ExistingRepo -eq '') {
  $repo = Join-Path $pkg 'hud-drive-cross-platform-controller'
  if (Test-Path $repo) { throw "Already exists: $repo. Supply -ExistingRepo to use an existing checkout." }
  git clone https://github.com/saraheom/hud-drive-cross-platform-controller.git $repo
  if ($LASTEXITCODE -ne 0) { throw 'Git clone failed.' }
} else {
  $repo = (Resolve-Path $ExistingRepo).Path
}
$head = (git -C $repo rev-parse HEAD).Trim()
Write-Host "Repository HEAD: $head"
if ($head -ne '89a1e1c3c54d66413db19f2892e6337aa128dbc8') {
  Write-Warning 'Source differs from reviewed Oct-31 HEAD; applying only when all exact anchors match.'
}
$dirty = git -C $repo status --porcelain
if ($dirty) { throw 'Repository contains local changes; commit/stash those first to avoid mixing changes.' }
git -C $repo switch -c $branch
if ($LASTEXITCODE -ne 0) { throw 'Cannot create local feature branch.' }
python (Join-Path $pkg 'apply_to_repo.py') $repo
if ($LASTEXITCODE -ne 0) { throw 'Patch failed, see error above.' }
Write-Host 'Changed files:'
git -C $repo status --short
if (-not $DoNotZip) {
  $dest = Join-Path $pkg 'HUD_Controller_v90.35.3.24.33_FULL_SOURCE.zip'
  if (Test-Path $dest) { Remove-Item $dest }
  # Export the changed working tree, excluding Git metadata and local *.bak files.
  $work = Join-Path $pkg '.packaging_worktree'
  if (Test-Path $work) { Remove-Item $work -Recurse -Force }
  New-Item -ItemType Directory -Path $work | Out-Null
  Get-ChildItem $repo -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
    Copy-Item $_.FullName -Destination $work -Recurse -Force
  }
  Get-ChildItem $work -Recurse -File -Filter '*.pre2433.bak' | Remove-Item -Force
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($work, $dest, [System.IO.Compression.CompressionLevel]::Optimal, $false)
  Remove-Item $work -Recurse -Force
  Write-Host "Full source ZIP: $dest"
}
Write-Host 'To publish after checks: git -C "$repo" add ios; git -C "$repo" commit -m "Recover map decoder over same TCP and stabilize speed tags"; git -C "$repo" push -u origin $branch'
