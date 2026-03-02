# Move-WinRE Script Review — Suggested Improvements

This document summarises findings from a review of `Move-WinRE/Move-WinRE.psm1` and the supporting files under `Tests/`.  
Issues are grouped by category and each item includes a brief explanation and a recommended fix.

---

## 1. Parameters Defined but Never Used

### `$IAcceptLicense` and `$Silent`

Both parameters are declared in the `param()` block but the function body ignores them entirely.  
The script always prints the license text and always prompts the user interactively, regardless of the values passed.

**Recommended fix:**

```powershell
if (-not $IAcceptLicense) {
    Write-Host $licenseText
    $response = Read-Host -Prompt "Press 'y' to continue or any other key to abort"
    if ($response -ne 'y') {
        Write-Host "Aborted."
        return
    }
}
```

Use `[switch]` instead of `[bool]` for boolean flags; this matches PowerShell conventions and allows callers to write `-IAcceptLicense` rather than `-IAcceptLicense $true`:

```powershell
[switch]$IAcceptLicense,
[switch]$Silent
```

---

## 2. `exit` Terminates the Entire PowerShell Session

Every early-exit path calls `exit`, which closes the whole PowerShell process rather than simply leaving the function. This is unexpected and destructive for callers who run the function inside an existing session.

**Recommended fix:** Replace every `exit` with `return`.

```powershell
# Before
Stop-Transcript
exit

# After
Stop-Transcript
return
```

---

## 3. No Administrator Privilege Check

The script performs low-level disk operations that require elevation, but it never verifies that it is running as an administrator. It will fail with cryptic errors if invoked from a non-elevated session.

**Recommended fix:** Add an early check at the top of the function:

```powershell
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This function must be run as Administrator."
    return
}
```

---

## 4. No Error Handling Around Critical Operations

Partition creation, formatting, file copying, and `ReAgentc.exe` calls can all fail silently or throw terminating errors that are not caught. A failure mid-way through the process can leave the system in a broken state (e.g., both the old and new partitions gone, recovery not re-enabled).

**Recommended fix:** Wrap destructive operations in `try/catch` blocks and clean up on failure:

```powershell
try {
    Remove-Partition -DiskNumber $winrePartition.DiskNumber `
                     -PartitionNumber $winrePartition.PartitionNumber `
                     -Confirm:$false -ErrorAction Stop
} catch {
    Write-Error "Failed to remove old WinRE partition: $_"
    # Re-enable recovery before exiting
    & C:\Windows\System32\ReAgentc.exe /enable
    Stop-Transcript
    return
}
```

---

## 5. Hardcoded Temporary Paths

The paths `C:\Windows\Temp\winre` and `C:\Windows\Temp\winreNew` are hardcoded throughout the script. If either path already exists from a previous failed run the script logs "Oh well Check Next time" and continues without validating the existing content, which can cause incorrect data to be copied to the new partition.

**Recommended fixes:**

- Define the paths as variables at the top of the function so they are easy to change:

```powershell
$winreTempPath    = Join-Path $env:SystemRoot 'Temp\winre'
$winreNewTempPath = Join-Path $env:SystemRoot 'Temp\winreNew'
```

- When the path already exists, verify it is empty (or contains the expected data) before proceeding, or remove it and recreate it.

---

## 6. Incomplete Handling of Existing Temp Path

When `C:\Windows\Temp\winre` already exists, the code outputs `" Oh well Check Next time"` and continues as if the path is safe to use. This stub logic is never finished and could cause the script to silently copy stale or incorrect data.

**Recommended fix:** Either clear and recreate the directory, or validate its contents before continuing:

```powershell
if (Test-Path -Path $winreTempPath) {
    Write-Host " - Removing existing temp path - " -ForegroundColor Yellow -NoNewline
    Remove-Item -Path $winreTempPath -Recurse -Force
    Write-Host "Done" -ForegroundColor Green
}
New-Item -Path $winreTempPath -ItemType Directory | Out-Null
```

---

## 7. Incomplete Function Documentation

The `.DESCRIPTION` block contains only `Desc`, which provides no useful information to users running `Get-Help Move-WinRE`.

**Recommended fix:**

```powershell
.DESCRIPTION
    Moves the Windows Recovery Environment (WinRE) partition to the end of the boot disk,
    then expands the preceding partition to fill the freed space.
    Requires Windows, a GPT disk, and an elevated PowerShell session.
```

---

## 8. Spelling Errors

Two spelling mistakes appear in the visible user-facing text:

| Location | Current text | Correction |
|---|---|---|
| License text (line 24) | `Move-WinPE.PS1` | `Move-WinRE.PS1` |
| License text (line 24) | `preceeding` | `preceding` |

---

## 9. `SupportsShouldProcess` Not Declared

Destructive operations (partition deletion, partition formatting, disabling recovery) should respect `-WhatIf` and `-Confirm` so that administrators can preview changes before applying them.

**Recommended fix:** Add `SupportsShouldProcess` to the `[CmdletBinding()]` attribute and guard destructive calls:

```powershell
[CmdletBinding(SupportsShouldProcess)]

# Example usage:
if ($PSCmdlet.ShouldProcess("Disk $($winrePartition.DiskNumber) Partition $($winrePartition.PartitionNumber)", "Remove WinRE partition")) {
    Remove-Partition -DiskNumber $winrePartition.DiskNumber `
                     -PartitionNumber $winrePartition.PartitionNumber `
                     -Confirm:$false
}
```

---

## 10. `Start-Transcript` Called Without a Path

`Start-Transcript` is called without specifying a `-Path`, so the transcript is saved to the default PowerShell transcript location, which varies by host and configuration. This makes it difficult to locate the log afterwards.

**Recommended fix:** Specify an explicit, predictable path:

```powershell
$transcriptPath = Join-Path $env:SystemRoot "Logs\Move-WinRE_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -Append
Write-Host "Logging to: $transcriptPath"
```

---

## 11. Inconsistent Cmdlet Capitalisation

PowerShell is case-insensitive, but the script mixes casing styles (`where-object`, `Where-Object`, `test-path`, `Test-Path`, `new-item`, `New-Item`). Following the approved verb-noun capitalisation convention (`Get-Disk`, `Where-Object`) improves readability and PSScriptAnalyzer compliance.

---

## 12. Module Manifest — `VariablesToExport`

In `Move-WinRE.psd1`, `VariablesToExport = '*'` exports all variables from the module. This is a common default but exposes module-internal variables unnecessarily.

**Recommended fix:** Set to an empty array since this module exports no variables:

```powershell
VariablesToExport = @()
```

---

## 13. Tests — Relative Paths

`Tests\TestPSModule.ps1` and `Tests\InvokePSAnalyzer.ps1` use relative paths (e.g., `..\MoveWinRe\Move-WinRE.psd1`). These break if the scripts are run from a directory other than `Tests\`.

**Recommended fix:** Resolve paths relative to the script file itself:

```powershell
$repoRoot = Split-Path -Parent $PSScriptRoot
Test-ModuleManifest -Path (Join-Path $repoRoot 'Move-WinRE\Move-WinRE.psd1') -ErrorAction Stop -Verbose
```

---

## 14. `Get-Partition` Parameter Name

Line 80 calls `Get-Partition -disk $disk`, but the correct parameter name is `-DiskNumber`. Passing a `Disk` object to `-disk` may work via pipeline binding in some PowerShell versions but is not the documented API and may break in future releases.

**Recommended fix:**

```powershell
$partitions = Get-Partition -DiskNumber $disk.Number
```

---

## Summary Table

| # | Category | Severity | Effort |
|---|---|---|---|
| 1 | Unused parameters (`$IAcceptLicense`, `$Silent`) | Medium | Low |
| 2 | `exit` instead of `return` | High | Low |
| 3 | No administrator privilege check | High | Low |
| 4 | No error handling around critical operations | High | Medium |
| 5 | Hardcoded temporary paths | Medium | Low |
| 6 | Incomplete existing-path handling | High | Low |
| 7 | Incomplete function documentation | Low | Low |
| 8 | Spelling errors in user-visible text | Low | Low |
| 9 | `SupportsShouldProcess` not declared | Medium | Low |
| 10 | `Start-Transcript` without a path | Low | Low |
| 11 | Inconsistent cmdlet capitalisation | Low | Low |
| 12 | `VariablesToExport = '*'` in manifest | Low | Low |
| 13 | Relative paths in test scripts | Low | Low |
| 14 | Wrong `Get-Partition` parameter name | Medium | Low |
