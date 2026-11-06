<#
.SYNOPSIS
    Builds the Sketch3D Android APK.

.DESCRIPTION
    Three steps:
      1. Assets  — turns the web build into an offline APK payload:
                   index.html (CDN -> local vendor files, service worker off),
                   three.js r128, DM Mono woff2, PWA icons.
      2. Rust    — compiles the wry/tao shell for the requested ABIs with
                   cargo-ndk and drops libsketch3d.so into app/src/main/jniLibs.
                   wry's build.rs also generates the Kotlin bridge classes.
      3. Gradle  — assembles the APK.

.EXAMPLE
    .\build-apk.ps1
    .\build-apk.ps1 -BuildType debug -Abis x86_64 -Install
    .\build-apk.ps1 -Abis arm64-v8a -SkipAssets
#>
[CmdletBinding()]
param(
    [string[]] $Abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64'),
    [ValidateSet('debug', 'release')] [string] $BuildType = 'release',
    [switch] $SkipAssets,
    [switch] $SkipRust,
    [switch] $Install,
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $NdkVersion = '27.1.12297006'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$androidDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path -Parent $androidDir
$appDir       = Join-Path $androidDir 'app'
$assetsDir    = Join-Path $appDir 'src/main/assets'
$vendorDir    = Join-Path $assetsDir 'vendor'
$iconsDir     = Join-Path $assetsDir 'icons'
$jniDir       = Join-Path $appDir 'src/main/jniLibs'
$rustDir      = Join-Path $androidDir 'rust'
$kotlinDir    = Join-Path $appDir 'src/main/kotlin/com/notebysebas/sketch3d'
$distDir      = Join-Path $androidDir 'dist'

function Write-Step($message) {
    Write-Host ''
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Invoke-Curl($url, $destination) {
    & curl.exe -sSfL --retry 3 --connect-timeout 20 -o $destination $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $destination)) {
        throw "Download failed: $url"
    }
}

# ── Toolchain discovery ────────────────────────────────────────────────────
if (-not $AndroidSdk) {
    $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
if (-not (Test-Path $AndroidSdk)) {
    throw "Android SDK not found. Pass -AndroidSdk <path>."
}

$ndkDir = Join-Path $AndroidSdk "ndk/$NdkVersion"
if (-not (Test-Path $ndkDir)) {
    $ndkRoot = Join-Path $AndroidSdk 'ndk'
    $fallback = Get-ChildItem $ndkRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $fallback) { throw "No NDK found under $ndkRoot" }
    $ndkDir = $fallback.FullName
    Write-Host "    NDK $NdkVersion not found, using $($fallback.Name)"
}

if (-not $env:JAVA_HOME) {
    $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'jdk-17*' } | Select-Object -First 1
    if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
}
if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    throw "JDK 17 not found. Set JAVA_HOME."
}

$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_NDK_HOME = $ndkDir
$env:NDK_HOME = $ndkDir

# ── 1. Assets ──────────────────────────────────────────────────────────────
if (-not $SkipAssets) {
    Write-Step 'Preparing web assets for the APK'

    foreach ($dir in @($assetsDir, $vendorDir, $iconsDir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $html = Get-Content -Raw (Join-Path $projectRoot 'index.html')

    $replacements = @(
        @(
            '<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>',
            '<script src="./vendor/three.min.js"></script>'
        ),
        @(
            '<link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@300;400;500&display=swap" rel="stylesheet">',
            '<link href="./vendor/fonts.css" rel="stylesheet">'
        )
    )

    foreach ($pair in $replacements) {
        $before = $html
        $html = $html.Replace($pair[0], $pair[1])
        if ($before -eq $html) {
            Write-Warning "Replacement did not match: $($pair[0].Substring(0, [Math]::Min(60, $pair[0].Length)))"
        }
    }

    # Service worker block can also be present with LF-only line endings.
    $html = [regex]::Replace(
        $html,
        "(?s)<script>\s*if\('serviceWorker' in navigator\)\{.*?</script>",
        '<script>/* service worker disabled in the native build: assets are local */</script>'
    )

    Set-Content -Path (Join-Path $assetsDir 'index.html') -Value $html -Encoding UTF8 -NoNewline
    Copy-Item (Join-Path $projectRoot 'manifest.json') (Join-Path $assetsDir 'manifest.json') -Force

    # Three.js r128 (same version as the web build)
    $three = Join-Path $vendorDir 'three.min.js'
    if (-not (Test-Path $three)) {
        Write-Host '    downloading three.js r128'
        Invoke-Curl 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js' $three
    }

    # DM Mono — keep the app offline-capable
    $fontsCss = Join-Path $vendorDir 'fonts.css'
    if (-not (Test-Path $fontsCss)) {
        Write-Host '    downloading DM Mono'
        $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'
        $css = (& curl.exe -sSfL -A $ua 'https://fonts.googleapis.com/css2?family=DM+Mono:wght@300;400;500&display=swap') -join "`n"
        $fontUrls = [regex]::Matches($css, 'url\((https://fonts\.gstatic\.com/[^)]+)\)') |
            ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        foreach ($url in $fontUrls) {
            $file = Split-Path $url -Leaf
            $dest = Join-Path $vendorDir $file
            if (-not (Test-Path $dest)) { Invoke-Curl $url $dest }
            $css = $css.Replace($url, "./$file")
        }
        Set-Content -Path $fontsCss -Value $css -Encoding UTF8
    }

    # PWA icons (referenced by manifest.json as icons/icon-NN.png)
    Get-ChildItem (Join-Path $projectRoot 'icon-*.png') -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $iconsDir $_.Name) -Force
    }

    # Launcher icon. The repo's icon-*.png files are actually JPEG data with a
    # .png extension, and AAPT refuses to compile those — so copy them with the
    # extension that matches their real format.
    $resDir = Join-Path $appDir 'src/main/res'
    $densityMap = @{
        'mdpi'    = 'icon-96.png'
        'hdpi'    = 'icon-144.png'
        'xhdpi'   = 'icon-192.png'
        'xxhdpi'  = 'icon-384.png'
        'xxxhdpi' = 'icon-512.png'
    }
    foreach ($density in $densityMap.Keys) {
        $src = Join-Path $projectRoot $densityMap[$density]
        if (-not (Test-Path $src)) { continue }
        $signature = [IO.File]::ReadAllBytes($src)[0..3]
        $isPng = ($signature[0] -eq 0x89 -and $signature[1] -eq 0x50 -and $signature[2] -eq 0x4E)
        $extension = if ($isPng) { 'png' } else { 'jpg' }
        $dir = Join-Path $resDir "mipmap-$density"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Get-ChildItem $dir -Filter 'ic_launcher.*' -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Copy-Item $src (Join-Path $dir "ic_launcher.$extension") -Force
    }

    Write-Host '    assets ready'
}

# ── 2. Rust ────────────────────────────────────────────────────────────────
if (-not $SkipRust) {
    Write-Step "Building the Rust shell ($($Abis -join ', '))"

    $env:WRY_ANDROID_PACKAGE = 'com.notebysebas.sketch3d'
    $env:WRY_ANDROID_LIBRARY = 'sketch3d'
    $env:WRY_ANDROID_KOTLIN_FILES_OUT_DIR = $kotlinDir

    New-Item -ItemType Directory -Force -Path $kotlinDir | Out-Null
    New-Item -ItemType Directory -Force -Path $jniDir | Out-Null

    $ndkArgs = @()
    foreach ($abi in $Abis) { $ndkArgs += @('-t', $abi) }
    $ndkArgs += @('-P', '24', '-o', $jniDir)

    $cargoArgs = @('ndk') + $ndkArgs + @('build')
    if ($BuildType -eq 'release') { $cargoArgs += '--release' }

    Push-Location $rustDir
    try {
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) { throw "cargo ndk failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }

    $generated = Get-ChildItem $kotlinDir -Filter '*.kt' | Select-Object -ExpandProperty Name
    Write-Host "    generated Kotlin bridge: $($generated -join ', ')"
}

# ── 3. Gradle ──────────────────────────────────────────────────────────────
Write-Step "Assembling the APK ($BuildType)"

Push-Location $androidDir
try {
    $task = if ($BuildType -eq 'release') { ':app:assembleRelease' } else { ':app:assembleDebug' }
    & (Join-Path $androidDir 'gradlew.bat') $task --console=plain
    if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$apk = Join-Path $appDir "build/outputs/apk/$BuildType/app-$BuildType.apk"
if (-not (Test-Path $apk)) { throw "APK not found at $apk" }

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$final = Join-Path $distDir "Sketch3D-v4.3-$BuildType.apk"
Copy-Item $apk $final -Force

$sizeMb = [Math]::Round((Get-Item $final).Length / 1MB, 1)
Write-Host ''
Write-Host "APK: $final ($sizeMb MB)" -ForegroundColor Green

if ($Install) {
    Write-Step 'Installing on the connected device'
    & adb install -r $final
    if ($LASTEXITCODE -ne 0) { throw 'adb install failed' }
    & adb shell am start -n com.notebysebas.sketch3d/.MainActivity | Out-Null
    Write-Host '    launched' -ForegroundColor Green
}
