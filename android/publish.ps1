<#
.SYNOPSIS
    Builds the release APK and publishes it as a GitHub Release asset.

.DESCRIPTION
    The APK is a binary: it never goes into the git history, it is uploaded
    as a release asset (https://github.com/<repo>/releases).

    Requires the `gh` CLI to be authenticated with an account that has write
    access to the target repository.

.EXAMPLE
    .\publish.ps1
    .\publish.ps1 -Repo kipzitox/Sketch3D-android -Tag v4.3-android -Notes "First Android build"
#>
[CmdletBinding()]
param(
    [string] $Repo = 'kipzitox/Sketch3D-android',
    [string] $Tag = '',
    [string] $Notes = 'Sketch3D Android build (Rust/wry shell, offline, exports to Downloads)',
    [string[]] $Abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
)

$ErrorActionPreference = 'Stop'

$androidDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Preflight ──────────────────────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) not found. Install it and run: gh auth login'
}
gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'gh is not authenticated. Run: gh auth login' }

$push = gh api "repos/$Repo" --jq '.permissions.push'
if ($LASTEXITCODE -ne 0) { throw "Repository $Repo not found or not accessible." }
if ($push -ne 'true') {
    throw "The authenticated gh account has no write access to $Repo.`n" +
          "Options: log in with the owner account (gh auth login --hostname github.com)," +
          " or ask the owner to add you as a collaborator."
}

# ── Build ──────────────────────────────────────────────────────────────────
Write-Host '==> Building the release APK' -ForegroundColor Cyan
& (Join-Path $androidDir 'build-apk.ps1') -BuildType release -Abis $Abis
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }

$apk = Get-ChildItem (Join-Path $androidDir 'dist') -Filter '*-release.apk' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $apk) { throw 'No APK found in dist/' }

# ── Publish ────────────────────────────────────────────────────────────────
if (-not $Tag) {
    $gradle = Join-Path $androidDir 'app\build.gradle.kts'
    $version = (Select-String -Path $gradle -Pattern 'versionName\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
    $Tag = "v$version-android"
}

Write-Host "==> Publishing $apk.Name to $Repo ($Tag)" -ForegroundColor Cyan

$existing = gh release view $Tag --repo $Repo --json tagName 2>$null
if ($LASTEXITCODE -eq 0) {
    gh release upload $Tag $apk.FullName --repo $Repo --clobber
    Write-Host "    uploaded to the existing release $Tag" -ForegroundColor Green
}
else {
    gh release create $Tag $apk.FullName --repo $Repo --title "Sketch3D ($Tag)" --notes $Notes
    Write-Host "    created release $Tag" -ForegroundColor Green
}

Write-Host ''
Write-Host "Done: https://github.com/$Repo/releases/tag/$Tag" -ForegroundColor Green
