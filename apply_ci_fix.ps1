param(
    [Parameter(Mandatory=$true)][string]$RepoPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $RepoPath -PathType Container)) { throw "Repository directory missing: $RepoPath" }
$python = Get-Command py -ErrorAction SilentlyContinue
if ($python) { & py -3 (Join-Path $PSScriptRoot 'apply_ci_fix.py') --repo $RepoPath }
elseif (Get-Command python -ErrorAction SilentlyContinue) { & python (Join-Path $PSScriptRoot 'apply_ci_fix.py') --repo $RepoPath }
else { throw 'Install Python 3 to apply this patch.' }
if ($LASTEXITCODE -ne 0) { throw 'Validation or patch failed; see output. No commit was created.' }
Push-Location $RepoPath
try {
    & git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Whitespace check failed; review the changes.' }
    & git status --short
    Write-Host 'Patch applied. Review git diff, then commit/push the three Swift files.' -ForegroundColor Green
} finally { Pop-Location }
