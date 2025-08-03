# Check if running as Administrator
#if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
#    Write-Warning "You must run this script as Administrator!"
#    exit 1
#}

# Enable verbose output
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

$logFile = "$env:TEMP\TadcoSetup.log"
function Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Tee-Object -FilePath $logFile -Append
}

Log "Starting Tadco setup script..."

# Enable verbose output
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

$logFile = "$env:TEMP\TadcoSetup.log"
function Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Tee-Object -FilePath $logFile -Append
}

Log "Starting Tadco setup script..."

# Step 1: Connect to WiFi (if not already done)
if (-not (Select-String -Path $logFile -Pattern "WIFI_CONNECTED" -Quiet)) {
    $SSID = "[UHL]WiFi"
    $Password = "uhl4life"
    Log "Creating WiFi profile for SSID: $SSID"
    $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
    $profilePath = "$env:TEMP\WiFiProfile.xml"
    $profileXml | Set-Content -Path $profilePath -Encoding UTF8
    netsh wlan add profile filename="$profilePath" | Out-Null
    netsh wlan connect name="$SSID" | Out-Null
    Start-Sleep -Seconds 10
    Log "WIFI_CONNECTED"
}

# Step 2: Set sleep timeout
if (-not (Select-String -Path $logFile -Pattern "SLEEP_CONFIGURED" -Quiet)) {
    Log "Setting sleep timeout (plugged in) to never"
    powercfg /change standby-timeout-ac 0
    Log "SLEEP_CONFIGURED"
}

# Step 3: Create local admin account
if (-not (Select-String -Path $logFile -Pattern "LOCAL_USER_CREATED" -Quiet)) {
    $userName = Read-Host "Enter the new local username"
    $userPassword = Read-Host "Enter password for $userName" -AsSecureString
    New-LocalUser -Name $userName -Password $userPassword -FullName $userName -Description "Tadco Roofing User"
    Add-LocalGroupMember -Group "Administrators" -Member $userName
    Log "LOCAL_USER_CREATED: $userName"
}

# Step 4: Rename computer
if (-not (Select-String -Path $logFile -Pattern "COMPUTER_RENAMED" -Quiet)) {
    $newComputerName = Read-Host "Enter the new computer name"
    Rename-Computer -NewName $newComputerName -Force
    Log "COMPUTER_RENAMED: $newComputerName"
}

# Enforce TLS 1.2 for secure downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Function to install MSI
function Install-MSI {
    param ([string]$url, [string]$fileName)
    $tempPath = "$env:TEMP\$fileName"
    Log "Downloading MSI from $url"
    Invoke-WebRequest -Uri $url -OutFile $tempPath -Verbose
    Log "Installing MSI $fileName"
    Start-Process "msiexec.exe" -ArgumentList "/i `"$tempPath`" /qn /norestart" -Wait
}

# Function to install EXE with timeout
function Install-EXE {
    param ([string]$url, [string]$fileName, [int]$timeoutSeconds = 30)
    $tempPath = "$env:TEMP\$fileName"
    Log "Downloading EXE from $url"
    Invoke-WebRequest -Uri $url -OutFile $tempPath -Verbose
    Log "Running EXE installer $fileName"
    $proc = Start-Process -FilePath $tempPath -ArgumentList "/quiet" -PassThru
    for ($i = 0; $i -lt $timeoutSeconds; $i++) {
        if ($proc.HasExited) {
            Log "$fileName exited after $i seconds"
            return
        }
        Start-Sleep -Seconds 1
    }
    Log "$fileName timeout reached, continuing"
}

# Step 5: Install Scout IT RMM
if (-not (Select-String -Path $logFile -Pattern "SCOUT_INSTALLED" -Quiet)) {
    Install-MSI -url "https://prod.setup.itsupport247.net/windows/BareboneAgent/32/Houston-Tadco_Roofing_Windows_OS_ITSPlatform_TKN70d4cf75-0098-416f-a5e2-f537d98f5d3b/MSI/setup" -fileName "Houston-Tadco_Roofing_Windows_OS_ITSPlatform_TKN70d4cf75-0098-416f-a5e2-f537d98f5d3b.msi"
    Log "SCOUT_INSTALLED"
}

# Step 6: Install Karr RMM
if (-not (Select-String -Path $logFile -Pattern "KARR_INSTALLED" -Quiet)) {
    Install-EXE -url "https://zinfandel.centrastage.net/csm/profile/downloadAgent/74f33f7d-6e2a-4eab-b945-ec5e6c0f03d6" -fileName "KarrRMM.exe" -timeoutSeconds 30
    Log "KARR_INSTALLED"
}

# Step 7: Install Bluebeam Revu
if (-not (Select-String -Path $logFile -Pattern "BLUEBEAM_INSTALLED" -Quiet)) {
    Install-EXE -url "https://bluebeam.com/FullRevuTRIAL" -fileName "BluebeamRevu.exe" -timeoutSeconds 45
    Log "BLUEBEAM_INSTALLED"
}

# Step 8: Update Microsoft Store apps
if (-not (Select-String -Path $logFile -Pattern "STORE_APPS_UPDATED" -Quiet)) {
    Log "Updating Microsoft Store apps"
    Get-AppxPackage -AllUsers | ForEach-Object {
        Try {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
        } Catch {
            Log "Failed to update app: $($_.Name)"
        }
    }
    Log "STORE_APPS_UPDATED"
}

# Step 9: Run Windows Updates
if (-not (Select-String -Path $logFile -Pattern "WINDOWS_UPDATES_INSTALLED" -Quiet)) {
    Log "Installing Windows Updates"
    Install-PackageProvider -Name NuGet -Force
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
    Import-Module PSWindowsUpdate
    Install-WindowsUpdate -AcceptAll -AutoReboot
    Log "WINDOWS_UPDATES_INSTALLED"
}



# Step 10: Run Chris Titus Tech's Windows 11 debloater
if (-not (Select-String -Path $logFile -Pattern "DEBLOATER_RAN" -Quiet)) {
    Log "Downloading Chris Titus Tech Windows 11 Debloater"
    $debloaterUrl = "https://github.com/ChrisTitusTech/winutil/releases/latest/download/winutil.ps1"
    $debloaterScript = "$env:TEMP\winutil.ps1"
    Invoke-WebRequest -Uri $debloaterUrl -OutFile $debloaterScript -UseBasicParsing

    Log "Running Windows 11 Debloater with recommended tweaks"
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$debloaterScript`"" -Verb RunAs
    Log "DEBLOATER_RAN"
}


try {
    # your entire script is above this block
    Log "Tadco setup script completed successfully."
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host "`nPress Enter to close..." -ForegroundColor Cyan
    Read-Host
}
