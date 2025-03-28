<#
.SYNOPSIS
    Azure Runbook: Install/update Edge and update Chrome on multiple Azure VMs using Invoke-AzVMRunCommand

.DESCRIPTION
    This runbook:
    - Checks for Google Chrome and runs the updater if present
    - Downloads and installs Microsoft Edge Enterprise silently
    - Runs inside multiple Azure VMs using Invoke-AzVMRunCommand

.PARAMETER VMNames
    Array of VM names to target

.PARAMETER ResourceGroupName
    Azure resource group containing the VMs
#>

param (
    [Parameter(Mandatory = $true)]
    [string[]] $VMNames,

    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
)

Import-Module Az.Compute

foreach ($vm in $VMNames) {
    Write-Output "⏳ Starting browser update on VM: $vm"

    $inlineScript = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
`$ProgressPreference = 'SilentlyContinue'

function Update-Chrome {
    `$chromePaths = @(
        `"$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe`",
        `"$env:ProgramFiles\Google\Chrome\Application\chrome.exe`"
    )
    `$found = `$false
    foreach (`$path in `$chromePaths) {
        if (Test-Path `$path) {
            `$found = `$true
        }
    }

    if (`$found) {
        `$updaterPaths = @(
            `"$env:ProgramFiles(x86)\Google\Update\GoogleUpdate.exe`",
            `"$env:ProgramFiles\Google\Update\GoogleUpdate.exe`"
        )
        foreach (`$updater in `$updaterPaths) {
            if (Test-Path `$updater) {
                Start-Process `$updater -ArgumentList "/ua /installsource scheduler" -Wait
                Write-Output "🔄 Chrome update triggered."
                return
            }
        }
        Write-Output "⚠️ Chrome found, but updater not found."
    } else {
        Write-Output "ℹ️ Chrome not installed."
    }
}

function Install-Edge {
    `$installerUrl = 'https://go.microsoft.com/fwlink/?linkid=2135547'
    `$tempFile = `"$env:TEMP\MicrosoftEdgeEnterpriseX64.msi`"
    Invoke-WebRequest -Uri `$installerUrl -OutFile `$tempFile -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList \"/i `"`$tempFile`" /quiet /norestart\" -Wait
    Remove-Item `$tempFile -Force
    Write-Output "✅ Microsoft Edge installed or updated successfully."
}

Update-Chrome
Install-Edge
"@

    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $vm `
            -CommandId 'RunPowerShellScript' -ScriptString $inlineScript -ErrorAction Stop

        foreach ($msg in $result.Value) {
            Write-Output "$($msg.Message)"
        }
        Write-Output "✔ Finished on $vm."
    }
    catch {
        Write-Output "❌ Failed on $vm: $_"
    }
}

Write-Output "🏁 Runbook complete."


Write-Output "All actions logged to Azure Automation job output."
