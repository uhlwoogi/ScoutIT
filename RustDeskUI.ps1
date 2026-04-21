# ScoutIT Remote Support (RustDesk) - Uninstall Script
$ErrorActionPreference = 'SilentlyContinue'

# ── Config ────────────────────────────────────────────────────────────────────
$rustdeskInstallDir = 'C:\Program Files\ScoutIT-RemoteSupport'
$rustdeskService    = 'ScoutIT-RemoteSupport'
$rustdeskMsiName    = 'estudio-scoutit-remotesupport'  # used to find uninstall key in registry

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Starting ScoutIT Remote Support uninstall..."

# ── Stop and unregister the service ──────────────────────────────────────────
$svc = Get-Service -Name $rustdeskService -ErrorAction SilentlyContinue
if ($null -ne $svc) {
    Write-Host "Stopping ScoutIT Remote Support service..."
    Stop-Service -Name $rustdeskService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Attempt graceful service uninstall via exe first
    $rustdeskExe = Get-ChildItem $rustdeskInstallDir -Filter '*.exe' -ErrorAction SilentlyContinue |
                   Select-Object -First 1
    if ($rustdeskExe) {
        Write-Host "Unregistering service via exe..."
        Start-Process -FilePath $rustdeskExe.FullName -ArgumentList '--uninstall-service' -Wait
        Start-Sleep -Seconds 5
    }
} else {
    Write-Host "Service '$rustdeskService' not found - may already be removed."
}

# ── MSI uninstall via registry ProductCode ───────────────────────────────────
Write-Host "Looking for MSI uninstall entry in registry..."
$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$productCode = $null
foreach ($key in $uninstallKeys) {
    $match = Get-ItemProperty $key -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match 'scoutit|remotesupport|rustdesk' -or
                            $_.Publisher  -match 'scoutit|rustdesk' } |
             Select-Object -First 1
    if ($match) {
        $productCode = $match.PSChildName
        Write-Host "Found uninstall entry: $($match.DisplayName) [$productCode]"
        break
    }
}

if ($productCode) {
    Write-Host "Running MSI uninstall..."
    Start-Process -FilePath "msiexec.exe" `
                  -ArgumentList "/x `"$productCode`" /qn /norestart" `
                  -Wait
    Start-Sleep -Seconds 10
    Write-Host "MSI uninstall complete."
} else {
    Write-Warning "No MSI uninstall entry found in registry. Falling back to manual removal."
}

# ── Kill any remaining processes ─────────────────────────────────────────────
Write-Host "Killing any remaining RustDesk processes..."
Get-Process | Where-Object { $_.Path -match 'ScoutIT-RemoteSupport|rustdesk|scoutit' } |
              Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ── Remove install directory ──────────────────────────────────────────────────
if (Test-Path $rustdeskInstallDir) {
    Write-Host "Removing install directory: $rustdeskInstallDir"
    Remove-Item -Path $rustdeskInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $rustdeskInstallDir) {
        Write-Warning "Directory still exists - may have locked files. You may need to reboot and re-run."
    } else {
        Write-Host "Install directory removed."
    }
} else {
    Write-Host "Install directory not found - already removed."
}

# ── Remove leftover AppData / config ─────────────────────────────────────────
$appDataPaths = @(
    "$env:APPDATA\ScoutIT-RemoteSupport",
    "$env:APPDATA\RustDesk",
    "$env:ProgramData\ScoutIT-RemoteSupport",
    "$env:ProgramData\RustDesk"
)
foreach ($path in $appDataPaths) {
    if (Test-Path $path) {
        Write-Host "Removing: $path"
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Confirm ───────────────────────────────────────────────────────────────────
$svcFinal = Get-Service -Name $rustdeskService -ErrorAction SilentlyContinue
$dirFinal = Test-Path $rustdeskInstallDir

Write-Output "................................................."
if ($null -eq $svcFinal -and -not $dirFinal) {
    Write-Output "ScoutIT Remote Support successfully uninstalled."
} else {
    if ($null -ne $svcFinal) { Write-Warning "Service '$rustdeskService' still present." }
    if ($dirFinal)            { Write-Warning "Install directory still present - reboot may be required." }
}
Write-Output "................................................."

exit 0
