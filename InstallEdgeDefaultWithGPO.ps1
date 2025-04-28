# This script is not signed, but needs to run under elevated privs. So, either sign it, or run it as shown on the following line:
# Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PWD\InstallEdgeDefaultWithGPO.ps1`"" -Verb RunAs

# Elevation Check
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Script not running as Administrator. Restarting with elevation..."
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

<#
.SYNOPSIS
    Local PowerShell: Chrome Removal, Edge Install, Set Edge as Default via GPO, and Log Actions.

.DESCRIPTION
    Removes Chrome if installed, installs Microsoft Edge silently, applies GPO setting to make Edge default browser, and logs all actions.

.NOTES
    Requires administrative privileges.
#>

# Variables
$logPath = "C:\Temp\InstallEdgeLog.txt"
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}
New-Item -Path $logPath -ItemType File -Force | Out-Null

# Helper: Log function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logPath -Append
}

# Check if Chrome is installed
function Test-ChromeInstalled {
    $chromePaths = @(
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
    )
    return $chromePaths | Where-Object { Test-Path $_ }
}

# Uninstall Chrome
function Remove-Chrome {
    Write-Log "Attempting to uninstall Chrome..."
    $chromeUninstallKeyPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $chromeFound = $false

    foreach ($keyPath in $chromeUninstallKeyPaths) {
        Get-ChildItem $keyPath | ForEach-Object {
            $displayName = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($displayName -like "*Google Chrome*") {
                $chromeFound = $true
                $uninstallString = (Get-ItemProperty $_.PSPath).UninstallString
                if ($uninstallString) {
                    Write-Log "Found Chrome uninstall string: $uninstallString"
                    if ($uninstallString -match "msiexec") {
                        Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /quiet /norestart" -Wait
                    } else {
                        Start-Process "cmd.exe" -ArgumentList "/c `"$uninstallString /silent /norestart`"" -Wait
                    }
                    Write-Log "Chrome uninstallation triggered."
                    return
                }
            }
        }
    }

    if (-not $chromeFound) {
        Write-Log "Chrome uninstall information not found."
    }
}

# Install Edge
function Install-Edge {
    try {
        $api = 'https://edgeupdates.microsoft.com/api/products?view=enterprise'
        $temp = "$env:TEMP"
        $channel = "Stable"
        $arch = "x64"
        $platform = "Windows"

        Write-Log "Downloading Edge information from Microsoft..."

        $response = Invoke-WebRequest -Uri $api -UseBasicParsing
        $json = $response.Content | ConvertFrom-Json

        $release = $json | Where-Object { $_.Product -eq $channel } |
            Select-Object -ExpandProperty Releases |
            Where-Object { $_.Architecture -eq $arch -and $_.Platform -eq $platform } |
            Sort-Object ProductVersion -Descending |
            Select-Object -First 1

        if ($release -eq $null) {
            Write-Log "No Edge release found. Aborting."
            return
        }

        $artifact = $release.Artifacts | Select-Object -First 1
        $msiUrl = $artifact.Location
        $msiPath = Join-Path $temp (Split-Path $msiUrl -Leaf)

        Write-Log "Downloading Edge installer from $msiUrl..."
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

        $hash = (Get-FileHash -Path $msiPath -Algorithm $artifact.HashAlgorithm).Hash
        if ($hash -ne $artifact.Hash) {
            Write-Log "Checksum mismatch. Downloaded file is corrupt."
            return
        }

        Write-Log "Installing Edge silently..."
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
        Write-Log "Edge installed successfully."
    }
    catch {
        Write-Log "Error during Edge installation: $_"
    }
}

# Apply GPO registry setting to make Edge default
function Set-EdgeAsDefaultGPO {
    try {
        Write-Log "Applying GPO settings to set Edge as default browser..."
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
            Write-Log "Created registry path: $regPath"
        }

        $assocXmlPath = "C:\Windows\System32\edge-associations.xml"

        $assocXmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
    <Association Identifier=".htm" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier=".html" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier="http" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier="https" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier=".shtml" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier=".xhtml" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier=".xht" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier=".webp" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
    <Association Identifier=".svg" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
</DefaultAssociations>
"@

        $assocXmlContent | Out-File -FilePath $assocXmlPath -Encoding UTF8 -Force
        Set-ItemProperty -Path $regPath -Name "DefaultAssociationsConfiguration" -Value $assocXmlPath

        Write-Log "GPO setting applied. Edge will be default browser after reboot."
    }
    catch {
        Write-Log "Error applying GPO settings: $_"
    }
}

# MAIN
Write-Log "=== Script Started ==="
if (Test-ChromeInstalled) {
    Write-Log "Chrome detected."
    Remove-Chrome
} else {
    Write-Log "Chrome not installed."
}

Install-Edge
Set-EdgeAsDefaultGPO
Write-Log "=== Script Finished ==="
