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
    Local PowerShell: Chrome Update, Edge Install, and Set Edge as Default via GPO

.DESCRIPTION
    Updates Chrome if installed, installs Microsoft Edge silently, and applies GPO setting to make Edge default browser.

.NOTES
    Requires administrative privileges.
#>

# Update Chrome if installed
function Test-ChromeInstalled {
    $paths = @(
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
    )
    return $paths | Where-Object { Test-Path $_ }
}

function Update-Chrome {
    Write-Host "Checking for Chrome Updater..."
    $updater = "${env:ProgramFiles(x86)}\Google\Update\GoogleUpdate.exe"
    if (!(Test-Path $updater)) {
        $updater = "${env:ProgramFiles}\Google\Update\GoogleUpdate.exe"
    }
    if (Test-Path $updater) {
        Start-Process $updater -ArgumentList "/ua /installsource scheduler" -Wait
        Write-Host "Chrome update triggered."
    } else {
        Write-Host "Google Updater not found."
    }
}

# Install Edge
function Install-Edge {
    $api = 'https://edgeupdates.microsoft.com/api/products?view=enterprise'
    $temp = "$env:TEMP"
    $channel = "Stable"
    $arch = "x64"
    $platform = "Windows"

    $response = Invoke-WebRequest -Uri $api -UseBasicParsing
    $json = $response.Content | ConvertFrom-Json
    $index = [array]::IndexOf($json.Product, $channel)

    $release = $json[$index].Releases |
        Where-Object { $_.Architecture -eq $arch -and $_.Platform -eq $platform } |
        Sort-Object ProductVersion -Descending |
        Select-Object -First 1

    $artifact = $release.Artifacts[0]
    $msiUrl = $artifact.Location
    $msiPath = Join-Path $temp (Split-Path $msiUrl -Leaf)
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

    $hash = (Get-FileHash -Path $msiPath -Algorithm $artifact.HashAlgorithm).Hash
    if ($hash -ne $artifact.Hash) {
        Write-Error "Checksum mismatch. Downloaded file is corrupt."
        return
    }

    Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
    Write-Host "Edge installed successfully."
}

# Apply GPO registry setting to make Edge default
function Set-EdgeAsDefaultGPO {
    Write-Host "Applying GPO settings to make Edge default browser..."
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "DefaultAssociationsConfiguration" -Value "C:\Windows\System32\edge-associations.xml"

    $assocXml = @"
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

    $assocXmlPath = "C:\Windows\System32\edge-associations.xml"
    $assocXml | Out-File -FilePath $assocXmlPath -Encoding UTF8 -Force
    Write-Host "Default browser association set via GPO. Reboot required to apply."
}

# MAIN
if (Test-ChromeInstalled) {
    Update-Chrome
} else {
    Write-Host "Chrome not installed."
}

Install-Edge
Set-EdgeAsDefaultGPO
