# Correct the three failing road-name XCTest expectations in the current HUD repository.
# Only replaces the exact old CurrentNavRoadIdentity.swift blob that was verified on GitHub.
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$rel = 'ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift'
$target = Join-Path $repo $rel
$source = Join-Path $PSScriptRoot $rel
$legacySha = '9b7fb932a90706e0e6b89fd66d4c81f0e03b46ef'
$fixedSha = '300fad3f5f1e91ef690774c385b36045d3865ca0'

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Missing repository file: $target"
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Missing packaged corrected file: $source"
}
& git -C $repo rev-parse --is-inside-work-tree | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Not a Git checkout: $repo" }
$currentSha = (& git hash-object -- "$target").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to fingerprint the current road-identity file.' }
$packageSha = (& git hash-object -- "$source").Trim()
if ($packageSha -ne $fixedSha) { throw 'Package checksum mismatch; do not apply.' }
if ($currentSha -eq $fixedSha) {
    Write-Host 'The corrected road-matching source is already present. No files modified.'
    exit 0
}
if ($currentSha -ne $legacySha) {
    throw "The repository road-identity file has unexpected changes ($currentSha); no overwrite performed. Review manually."
}
Copy-Item -LiteralPath $source -Destination $target -Force
& git -C $repo diff --check -- $rel
if ($LASTEXITCODE -ne 0) { throw 'Git whitespace validation failed for the hotfix; inspect the diff.' }
Write-Host 'Applied and whitespace-checked the one-file CI hotfix.'
Write-Host 'Review: git -C <REPO> diff -- ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift'
Write-Host 'Then commit and push to rerun iOS CI. Adapter firmware and music/video code are untouched.'
