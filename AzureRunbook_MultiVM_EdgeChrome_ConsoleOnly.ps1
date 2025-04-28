<#
.SYNOPSIS
    Azure Runbook: Remove Chrome and install/update Edge on multiple Azure VMs using Invoke-AzVMRunCommand.

.DESCRIPTION
    This runbook:
    - Checks for Google Chrome and uninstalls it if present
    - Downloads and installs Microsoft Edge Enterprise silently
    - Runs inside multiple Azure VMs using Invoke-AzVMRunCommand

.PARAMETER VMNames
    Array of VM names to target.

.PARAMETER ResourceGroupName
    Azure resource group containing the VMs.
#>

param (
    [Parameter(Mandatory = $true)]
    [string[]] $VMNames,

    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
)

Import-Module Az.Compute

foreach ($vm in $VMNames) {
    Write-Output "Starting browser update on VM: $vm"

    $inlineScript = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
`$ProgressPreference = 'SilentlyContinue'

function Test-ChromeInstalled {
    `$paths = @(
        `"$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe`",
        `"$env:ProgramFiles\Google\Chrome\Application\chrome.exe`"
    )
    foreach (`$path in `$paths) {
        if (Test-Path `$path) {
            return `$true
        }
    }
    return `$false
}

function Remove-Chrome {
    Write-Output "Attempting to uninstall Chrome..."
    `$uninstallKeyPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach (`$keyPath in `$uninstallKeyPaths) {
        Get-ChildItem `$keyPath -ErrorAction SilentlyContinue | ForEach-Object {
            `$displayName = (Get-ItemProperty \$_ -ErrorAction SilentlyContinue).DisplayName
            if (`$displayName -like "*Google Chrome*") {
                `$uninstallString = (Get-ItemProperty \$_).UninstallString
                if (`$uninstallString) {
                    Write-Output "Found Chrome uninstall string: `$uninstallString"
                    if (`$uninstallString -match "msiexec") {
                        Start-Process msiexec.exe -ArgumentList "/x `$(`$_.PSChildName) /quiet /norestart" -Wait
                    } else {
                        Start-Process "cmd.exe" -ArgumentList "/c `"`$uninstallString /silent /norestart`"" -Wait
                    }
                    Write-Output "Chrome uninstallation triggered."
                    return
                }
            }
        }
    }

    Write-Output "Chrome uninstall information not found."
}

function Install-Edge {
    try {
        `$api = 'https://edgeupdates.microsoft.com/api/products?view=enterprise'
        `$temp = "`$env:TEMP"
        `$channel = "Stable"
        `$arch = "x64"
        `$platform = "Windows"

        Write-Output "Fetching Edge download info..."
        `$response = Invoke-WebRequest -Uri `$api -UseBasicParsing
        `$json = `$response.Content | ConvertFrom-Json

        `$release = `$json | Where-Object { `$_.Product -eq `$channel } |
            Select-Object -ExpandProperty Releases |
            Where-Object { `$_.Architecture -eq `$arch -and `$_.Platform -eq `$platform } |
            Sort-Object ProductVersion -Descending |
            Select-Object -First 1

        if (`$release -eq `$null) {
            Write-Output "No Edge release found."
            return
        }

        `$artifact = `$release.Artifacts | Select-Object -First 1
        `$msiUrl = `$artifact.Location
        `$msiPath = Join-Path `$temp (Split-Path `$msiUrl -Leaf)

        Write-Output "Downloading Edge installer..."
        Invoke-WebRequest -Uri `$msiUrl -OutFile `$msiPath -UseBasicParsing

        Write-Output "Installing Edge silently..."
        Start-Process msiexec.exe -ArgumentList "/i `"`$msiPath`" /quiet /norestart" -Wait

        Write-Output "Edge installed successfully."

        # Clean up
        Remove-Item `$msiPath -Force
    }
    catch {
        Write-Output "Error during Edge installation: `$($_.Exception.Message)"
    }
}

if (Test-ChromeInstalled) {
    Write-Output "Chrome detected."
    Remove-Chrome
} else {
    Write-Output "Chrome not installed."
}

Install-Edge
"@

    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $vm `
            -CommandId 'RunPowerShellScript' -ScriptString $inlineScript -ErrorAction Stop

        foreach ($msg in $result.Value) {
            Write-Output "$($msg.Message)"
        }
        Write-Output "Finished on $vm."
    }
    catch {
        Write-Output "Failed on $vm. Error: $_"
    }
}

Write-Output "Runbook complete."
Write-Output "All actions logged to Azure Automation job output."
