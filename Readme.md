
# Edge and Chrome Installer Automation

This solution provides two scripts for automating the update of Microsoft Edge and Google Chrome:

---

## 📘 Azure Runbook: Multi-VM Browser Installer

**File:** `AzureRunbook_MultiVM_EdgeChrome_ConsoleOnly.ps1`

### ✅ What it does:
- Runs on **multiple Azure VMs**.
- Installs or updates **Microsoft Edge**.
- Checks for and updates **Google Chrome** if installed.
- Logs output to the **Azure Automation Job Output**.

### 🚀 How to use:

1. **Import into Azure Automation**
   - Go to your Azure Automation Account.
   - Navigate to **Runbooks** > **Import a runbook**.
   - Upload `AzureRunbook_MultiVM_EdgeChrome_ConsoleOnly.ps1`.
   - Publish the runbook.

2. **Run the runbook**
   - Click **Start**.
   - Provide the required parameters:
     - `VMNames`: array of Azure VM names (e.g. `["vm1", "vm2"]`)
     - `ResourceGroupName`: name of the resource group containing the VMs

> 💡 This uses `Invoke-AzVMRunCommand`, so no need for Hybrid Workers.

---

## 🖥️ Local Script: Edge Installer with GPO Association

**File:** `InstallEdgeDefaultWithGPO.ps1`

### ✅ What it does:
- Automatically **elevates to Administrator**.
- **Bypasses script execution policy**.
- Updates **Google Chrome** if installed.
- Installs **Microsoft Edge silently**.
- Configures a **GPO-based default browser association** to Edge.

### 🚀 How to use:

1. **Right-click and Run with PowerShell (as Administrator)**  
   Or run from a terminal:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\InstallEdgeDefaultWithGPO.ps1
   ```   
   If that doesn't work run the following:
   ```powershell
   Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PWD\InstallEdgeDefaultWithGPO.ps1`"" -Verb RunAs
   ```

2. ✅ The script will:
   - Elevate privileges if needed.
   - Install Edge and Chrome updates.
   - Configure default browser settings via registry and XML GPO file.

> 🛑 Requires reboot to fully apply the GPO default browser settings.

---

## 🛠 Optional Enhancements

- You can configure scheduled runs using Azure Automation or Task Scheduler.

---

## 📂 Files

- `AzureRunbook_MultiVM_EdgeChrome_ConsoleOnly.ps1` — Azure Automation script for Azure VMs.
- `InstallEdgeDefaultWithGPO.ps1` — Local script for workstations or servers.

