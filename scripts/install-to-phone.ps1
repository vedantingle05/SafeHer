# Build SafeHer and install on USB-connected phone via adb
$ErrorActionPreference = "Continue"
$Log = "d:\safeher\safeher1\safeher\safeher-apk\install-log.txt"
$Frontend = "d:\safeher\safeher1\safeher\safeher\frontend"
$Backend = "d:\safeher\safeher1\safeher\safeher\backend"

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $Log -Value $line
}

New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null
"=== SafeHer install $(Get-Date) ===" | Set-Content $Log

# D: caches (C: is full)
$env:PUB_CACHE = "D:\flutter-cache\pub-cache"
$env:GRADLE_USER_HOME = "D:\flutter-cache\gradle"
$env:TEMP = "D:\flutter-cache\temp"
$env:TMP = "D:\flutter-cache\temp"
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:TEMP | Out-Null

# LAN IP for API
$LanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -match '^192\.168\.' } |
    Select-Object -First 1).IPAddress
if (-not $LanIp) { $LanIp = "192.168.1.8" }
Log "API base: http://${LanIp}:5000/api"

# ADB
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
    $adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
}
if (-not (Test-Path $adb)) {
    Log "ERROR: adb not found. Install Android SDK Platform-Tools."
    exit 1
}

Log "ADB: $adb"
& $adb kill-server 2>&1 | Out-Null
Start-Sleep -Seconds 1
& $adb start-server 2>&1 | Out-Null
$devices = & $adb devices 2>&1
Log "Devices:`n$($devices -join "`n")"

if ($devices -notmatch "device$") {
    Log "ERROR: No authorized device. On phone: enable USB debugging, use File Transfer mode, tap Allow on RSA prompt."
    exit 1
}

# Bootstrap D: Android SDK if needed
$SdkSrc = "$env:LOCALAPPDATA\Android\sdk"
$SdkDst = "D:\Android\Sdk"
if (-not (Test-Path "$SdkDst\platforms\android-33\android.jar")) {
    Log "Copying SDK to D:\Android\Sdk ..."
    New-Item -Force -ItemType Directory -Path "$SdkDst\platforms","$SdkDst\ndk","$SdkDst\build-tools" | Out-Null
    if (Test-Path "$SdkSrc\platforms\android-34") {
        robocopy "$SdkSrc\platforms\android-34" "$SdkDst\platforms\android-33" /E /NFL /NDL /NJH /NJS | Out-Null
        @"
Pkg.Desc=Android SDK Platform 33
AndroidVersion.ApiLevel=33
Pkg.Revision=3
"@ | Set-Content "$SdkDst\platforms\android-33\source.properties"
    }
    foreach ($p in @("android-36")) {
        if (Test-Path "$SdkSrc\platforms\$p") {
            robocopy "$SdkSrc\platforms\$p" "$SdkDst\platforms\$p" /E /NFL /NDL /NJH /NJS | Out-Null
        }
    }
    if (Test-Path "$SdkSrc\ndk\28.2.13676358") {
        robocopy "$SdkSrc\ndk\28.2.13676358" "$SdkDst\ndk\28.2.13676358" /E /NFL /NDL /NJH /NJS | Out-Null
    }
    $bt = Get-ChildItem "$SdkSrc\build-tools" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($bt) { robocopy $bt.FullName "$SdkDst\build-tools\$($bt.Name)" /E /NFL /NDL /NJH /NJS | Out-Null }
    if (Test-Path "$SdkSrc\platform-tools") {
        robocopy "$SdkSrc\platform-tools" "$SdkDst\platform-tools" /E /NFL /NDL /NJH /NJS | Out-Null
    }
}

$lp = Join-Path $Frontend "android\local.properties"
$lines = @()
if (Test-Path $lp) { $lines = Get-Content $lp | Where-Object { $_ -notmatch '^sdk\.dir=' } }
$lines += "sdk.dir=D:\\Android\\Sdk"
$lines | Set-Content $lp

# Backend
$backendUp = $false
try {
    $r = Invoke-WebRequest -Uri "http://localhost:5000/" -UseBasicParsing -TimeoutSec 2
    $backendUp = $r.StatusCode -eq 200
} catch {}
if (-not $backendUp) {
    Log "Starting backend..."
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d `"$Backend`" && npm start" -WindowStyle Minimized
    Start-Sleep -Seconds 4
}

Set-Location $Frontend
Log "flutter pub get..."
flutter pub get 2>&1 | ForEach-Object { Log $_ }

Log "Building and installing on device (debug, may take 10-15 min)..."
$apiDefine = "--dart-define=API_BASE_URL=http://${LanIp}:5000/api"
flutter install --debug $apiDefine.Split(' ') 2>&1 | ForEach-Object { Log $_ }

if ($LASTEXITCODE -ne 0) {
    Log "flutter install failed, trying build apk + adb install..."
    flutter build apk --debug $apiDefine.Split(' ') 2>&1 | ForEach-Object { Log $_ }
    $apk = Join-Path $Frontend "build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $apk) {
        & $adb install -r $apk 2>&1 | ForEach-Object { Log $_ }
    } else {
        Log "ERROR: APK not built. Free space on C: drive (need ~5 GB) then re-run this script."
        exit 1
    }
}

Log "DONE. Open SafeHer on your phone. Keep backend running on PC."
Log "If profile fails, phone must reach http://${LanIp}:5000"
