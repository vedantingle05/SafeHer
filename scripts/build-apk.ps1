# SafeHer APK build script — uses D: drive for caches (C: is often full)
$ErrorActionPreference = "Stop"

$ProjectRoot = "d:\safeher\safeher1\safeher\safeher\frontend"
$SdkSource   = "$env:LOCALAPPDATA\Android\sdk"
$SdkDest     = "D:\Android\Sdk"
$OutDir      = "d:\safeher\safeher1\safeher\safeher-apk"

# Prefer an explicit override for hotspot or public backend host.
$ApiUrlEnv = $env:SAFEHER_API_URL
$ApiHostEnv = $env:SAFEHER_API_HOST

if ($ApiUrlEnv) {
    $ApiBaseUrl = $ApiUrlEnv.Trim().TrimEnd('/')
} elseif ($ApiHostEnv) {
    $Host = $ApiHostEnv.Trim()
    if ($Host -notmatch '^https?://') {
        $Host = "http://$Host"
    }
    $Host = $Host.TrimEnd('/')
    if ($Host -match '/api$') {
        $ApiBaseUrl = $Host
    } elseif ($Host -match ':[0-9]+$') {
        $ApiBaseUrl = "$Host/api"
    } else {
        $ApiBaseUrl = "$Host:5000/api"
    }
} else {
    $LanIp = (
        Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -notlike '0.*' -and
            $_.IPAddress -notlike '255.*'
        } |
        Select-Object -First 1
    ).IPAddress
    if (-not $LanIp) { $LanIp = "192.168.1.8" }
    $ApiBaseUrl = "http://${LanIp}:5000/api"
}

Write-Host "==> SafeHer APK build"
Write-Host "    API URL: $ApiBaseUrl"
Write-Host "    SDK dest: $SdkDest"

# Caches on D:
$env:PUB_CACHE       = "D:\flutter-cache\pub-cache"
$env:GRADLE_USER_HOME = "D:\flutter-cache\gradle"
$env:TEMP            = "D:\flutter-cache\temp"
$env:TMP             = "D:\flutter-cache\temp"
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:TEMP, $OutDir | Out-Null

# Bootstrap minimal SDK on D: (platform 33 + 36, NDK 28.2, build-tools)
if (-not (Test-Path "$SdkDest\platforms\android-33\android.jar")) {
    Write-Host "==> Copying Android SDK components to D: (one-time)..."
    New-Item -ItemType Directory -Force -Path "$SdkDest\platforms", "$SdkDest\ndk", "$SdkDest\build-tools" | Out-Null
    if (Test-Path "$SdkSource\platforms\android-34") {
        robocopy "$SdkSource\platforms\android-34" "$SdkDest\platforms\android-33" /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        @"
Pkg.Desc=Android SDK Platform 33
Pkg.UserSrc=false
Platform.Version=13
Platform.CodeName=
Pkg.Revision=3
AndroidVersion.ApiLevel=33
"@ | Set-Content "$SdkDest\platforms\android-33\source.properties" -Encoding ASCII
    }
    if (Test-Path "$SdkSource\platforms\android-36") {
        robocopy "$SdkSource\platforms\android-36" "$SdkDest\platforms\android-36" /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    }
    if (Test-Path "$SdkSource\ndk\28.2.13676358") {
        robocopy "$SdkSource\ndk\28.2.13676358" "$SdkDest\ndk\28.2.13676358" /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    }
    $bt = Get-ChildItem "$SdkSource\build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($bt) {
        robocopy $bt.FullName "$SdkDest\build-tools\$($bt.Name)" /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    }
    if (Test-Path "$SdkSource\platform-tools") {
        robocopy "$SdkSource\platform-tools" "$SdkDest\platform-tools" /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    }
}

# Point Flutter at D: SDK
$localProps = Join-Path $ProjectRoot "android\local.properties"
$sdkLine = "sdk.dir=$($SdkDest -replace '\\','\\\\')"
if (Test-Path $localProps) {
    $content = Get-Content $localProps | Where-Object { $_ -notmatch "^sdk\.dir=" }
    ($content + $sdkLine) | Set-Content $localProps
} else {
    $sdkLine | Set-Content $localProps
}

Set-Location $ProjectRoot
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=$ApiBaseUrl

$apk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    $apk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-debug.apk"
}
if (-not (Test-Path $apk)) { throw "APK not found after build." }

$dest = Join-Path $OutDir "safeher-$(Get-Date -Format 'yyyyMMdd-HHmm').apk"
Copy-Item $apk $dest -Force
Write-Host ""
Write-Host "SUCCESS: $dest"
Write-Host "Install on phone: adb install `"$dest`""
