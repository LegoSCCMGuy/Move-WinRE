function Move-WinRE {
    <#
    .SYNOPSIS
    Moves a Windows RE Partition to the end of the disk

    .DESCRIPTION
    Moves the Windows Recovery Environment (WinRE) partition to the end of the boot disk,
    then expands the preceding partition to fill the freed space.
    Requires Windows, a GPT disk, and an elevated PowerShell session.

    .PARAMETER IAcceptLicense
    When specified, the license agreement is accepted automatically and the interactive prompt is skipped.

    .PARAMETER Silent
    When specified, suppresses interactive prompts. Requires -IAcceptLicense to also be specified.

    .EXAMPLE
    PS C:\> Move-WinRE -IAcceptLicense
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [switch]
        $IAcceptLicense,
        [Parameter()]
        [switch]
        $Silent
    )

    # Elevation check
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This function must be run as Administrator."
        return
    }

    $transcriptPath = Join-Path $env:SystemRoot "Logs\Move-WinRE_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath -Append

    $licenseText = @"
Move-WinRE.PS1 - Used to move a windows recovery partition to the end of an expanded disk and expand the preceding partition.
Copyright (C) 2023 Barry Harriman

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
"@

    if (-not $IAcceptLicense) {
        Write-Host $licenseText
        Write-Host ""
        if ($Silent) {
            Write-Error "License must be accepted with -IAcceptLicense when using -Silent."
            Stop-Transcript
            return
        }
        $response = Read-Host -Prompt "Press 'y' to continue or any other key to abort"
        if ($response -ne 'y') {
            Write-Host "Aborted."
            Stop-Transcript
            return
        }
    }

    Write-Host ""
    Write-Host "Starting Process" -ForegroundColor White
    Write-Host "-Gathering Disk Configs" -NoNewline -ForegroundColor White

    $disk = Get-Disk | Where-Object { $_.IsBoot -eq $true }

    if ($null -eq $disk) {
        Write-Host "*** Error Selecting Disks ***" -ForegroundColor Red
        Stop-Transcript
        return
    }
    else {
        Write-Host " +Found Boot Disk" -ForegroundColor Green
    }

    $currentSize = $disk.Size / 1024 / 1024 / 1024
    $allocatedSize = $disk.AllocatedSize / 1024 / 1024 / 1024
    Write-Host " Current Disk Size: $($currentSize)GB"
    Write-Host " Current Allocated Size: $($allocatedSize)GB"

    if ($currentSize - $allocatedSize -le 1) {
        Write-Host " Not enough Free Space on Disk. Expecting over 1GB Free Exiting.." -ForegroundColor Red
        Stop-Transcript
        return
    }
    else {
        Write-Host " - Checking Partitions Order" -ForegroundColor Yellow

        $partitions = Get-Partition -DiskNumber $disk.Number

        Write-Host "   Number of Partitions Found: $($partitions.Count)" -ForegroundColor Green
        Write-Host " - Finding Recovery Partitions - " -NoNewline -ForegroundColor Yellow
        $winrePartition = $partitions | Where-Object { $_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' }
        if ($null -eq $winrePartition) {
            Write-Host "No WinRE Partitions Found. Exiting... " -ForegroundColor Red
            Stop-Transcript
            return
        }
        else {
            Write-Host "WinRE Partition Found!" -ForegroundColor Green
            Write-Host " - Evaluating WinRE Partition - " -NoNewline -ForegroundColor Yellow
            if ($partitions.Count -ne $winrePartition.PartitionNumber) {
                Write-Host "Not Last Partition. Aborting" -ForegroundColor Red
                Stop-Transcript
                return
            }
            else {
                Write-Host "Confirmed Partition is last current partition" -ForegroundColor Green

                $winreTempPath = Join-Path $env:SystemRoot 'Temp\winre'
                $winreNewTempPath = Join-Path $env:SystemRoot 'Temp\winreNew'

                Write-Host " - Checking for WinRE TempPath - " -NoNewline -ForegroundColor Yellow
                if (Test-Path -Path $winreTempPath) {
                    Write-Host "Path Exists! Removing stale path." -ForegroundColor Yellow
                    Remove-Item -Path $winreTempPath -Recurse -Force
                }
                Write-Host " - Creating Temp Path for WinRE - " -ForegroundColor Yellow -NoNewline
                New-Item -Path $winreTempPath -ItemType Directory | Out-Null
                Write-Host "Created Path" -ForegroundColor Green

                Write-Host " - Mapping WinRE Partition to Temp Path - " -ForegroundColor Yellow -NoNewline
                try {
                    Add-PartitionAccessPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -AccessPath $winreTempPath -ErrorAction Stop
                }
                catch {
                    Write-Error "Failed to map WinRE partition to temp path: $_"
                    Stop-Transcript
                    return
                }
                Write-Host "Mapped WinRE to temp path" -ForegroundColor Green

                Write-Host " - Checking WinRE Partition - " -NoNewline -ForegroundColor Yellow
                if (Test-Path -Path "$winreTempPath\Recovery\WindowsRE\Winre.wim") {
                    Write-Host "Found the WinRE WIM file and will proceed" -ForegroundColor Green
                }
                else {
                    Write-Host "Not sure on the WinRE partition so aborting" -ForegroundColor Red
                    Write-Host " - Cleaning Up" -ForegroundColor Red
                    Write-Host "   - Removing Mapping" -ForegroundColor Red
                    Remove-PartitionAccessPath -AccessPath $winreTempPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                    Write-Host "Ending Process" -ForegroundColor Red
                    Stop-Transcript
                    return
                }

                Write-Host " - Creating new partition - " -NoNewline -ForegroundColor Yellow
                if ($PSCmdlet.ShouldProcess("Disk $($winrePartition.DiskNumber)", "Create new WinRE partition")) {
                    try {
                        $partitionOffset = $disk.Size - ($winrePartition.Size + (1 * 1024 * 1024))
                        $newWinREPartition = New-Partition -Offset $partitionOffset -Size $winrePartition.Size -DiskNumber $winrePartition.DiskNumber -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -ErrorAction Stop
                    }
                    catch {
                        Write-Error "Failed to create new WinRE partition: $_"
                        Remove-PartitionAccessPath -AccessPath $winreTempPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                        Stop-Transcript
                        return
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Formatting new partition - " -NoNewline -ForegroundColor Yellow
                    try {
                        Get-Volume -Partition $newWinREPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel Recovery -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Error "Failed to format new WinRE partition: $_"
                        Remove-PartitionAccessPath -AccessPath $winreTempPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                        Stop-Transcript
                        return
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Checking Temp Path for New WinRE - " -ForegroundColor Yellow -NoNewline
                    if (Test-Path -Path $winreNewTempPath) {
                        Write-Host "Path Exists! Removing stale path." -ForegroundColor Yellow
                        Remove-Item -Path $winreNewTempPath -Recurse -Force
                    }
                    Write-Host " - Creating Temp Path for New WinRE - " -ForegroundColor Yellow -NoNewline
                    New-Item -Path $winreNewTempPath -ItemType Directory | Out-Null
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Adding access Path to New WinRE - " -ForegroundColor Yellow -NoNewline
                    try {
                        Add-PartitionAccessPath -AccessPath $winreNewTempPath -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber -ErrorAction Stop
                    }
                    catch {
                        Write-Error "Failed to map new WinRE partition: $_"
                        Remove-PartitionAccessPath -AccessPath $winreTempPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                        Stop-Transcript
                        return
                    }
                    Write-Host "Done!" -ForegroundColor Green

                    Write-Host " - Copying Data - " -ForegroundColor Yellow -NoNewline
                    try {
                        Copy-Item -Path "$winreTempPath\Recovery" -Destination $winreNewTempPath -Container -Recurse -ErrorAction Stop
                    }
                    catch {
                        Write-Error "Failed to copy WinRE data: $_"
                        Remove-PartitionAccessPath -AccessPath $winreNewTempPath -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
                        Remove-PartitionAccessPath -AccessPath $winreTempPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                        Stop-Transcript
                        return
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host "Disconnecting Mapped Access Paths" -ForegroundColor White
                    Write-Host " - Removing Mapping for New Recovery Partition - " -NoNewline -ForegroundColor Yellow
                    Remove-PartitionAccessPath -AccessPath $winreNewTempPath -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
                    Write-Host "Done" -ForegroundColor Green
                    Write-Host " - Removing Mapping for Old Recovery Partition - " -NoNewline -ForegroundColor Yellow
                    Remove-PartitionAccessPath -AccessPath $winreTempPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                    Write-Host " Done!" -ForegroundColor Green

                    Write-Host "Fixing Recovery Partitions and Settings" -ForegroundColor White

                    Write-Host " - Disabling Recovery Partition - " -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess("WinRE", "Disable recovery agent")) {
                        $disableResult = & "$env:SystemRoot\system32\ReAgentc.exe" /disable
                        if ($LASTEXITCODE -ne 0) {
                            Write-Error "ReAgentc.exe /disable failed (exit code $LASTEXITCODE): $disableResult"
                            Stop-Transcript
                            return
                        }
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Removing old Recovery Partition - " -NoNewline -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess("Disk $($winrePartition.DiskNumber) Partition $($winrePartition.PartitionNumber)", "Remove old WinRE partition")) {
                        try {
                            Remove-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -Confirm:$false -ErrorAction Stop
                        }
                        catch {
                            Write-Error "Failed to remove old WinRE partition: $_"
                            $reenableResult = & "$env:SystemRoot\System32\ReAgentc.exe" /enable
                            if ($LASTEXITCODE -ne 0) {
                                Write-Warning "ReAgentc.exe /enable also failed during cleanup (exit code $LASTEXITCODE): $reenableResult"
                            }
                            Stop-Transcript
                            return
                        }
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Setting Recovery Partition Path - " -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess("WinRE", "Set recovery image path")) {
                        $winrePathSet = "\\?\GLOBALROOT\device\harddisk$($newWinREPartition.DiskNumber)\partition$($newWinREPartition.PartitionNumber)\Recovery\WindowsRE"
                        $setResult = & "$env:SystemRoot\System32\ReAgentc.exe" /setreimage /path $winrePathSet /target "$env:SystemRoot"
                        if ($LASTEXITCODE -ne 0) {
                            Write-Error "ReAgentc.exe /setreimage failed (exit code $LASTEXITCODE): $setResult"
                            Stop-Transcript
                            return
                        }
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Enabling Recovery Partition - " -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess("WinRE", "Enable recovery agent")) {
                        $enableResult = & "$env:SystemRoot\System32\ReAgentc.exe" /enable
                        if ($LASTEXITCODE -ne 0) {
                            Write-Error "ReAgentc.exe /enable failed (exit code $LASTEXITCODE): $enableResult"
                            Stop-Transcript
                            return
                        }
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host "Fixing Partitions" -ForegroundColor White

                    Write-Host " - Resizing Partition Before New Recovery Partition - " -NoNewline -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess("Disk $($winrePartition.DiskNumber) Partition $($winrePartition.PartitionNumber - 1)", "Resize partition to maximum")) {
                        try {
                            $size = Get-PartitionSupportedSize -DiskNumber $winrePartition.DiskNumber -PartitionNumber ($winrePartition.PartitionNumber - 1) -ErrorAction Stop
                            Resize-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber ($winrePartition.PartitionNumber - 1) -Size $size.SizeMax -ErrorAction Stop
                        }
                        catch {
                            Write-Error "Failed to resize partition: $_"
                            Stop-Transcript
                            return
                        }
                    }
                    Write-Host "Done" -ForegroundColor Green

                    Write-Host " - Setting Attributes on Recovery Partition - " -NoNewline -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess("Disk $($newWinREPartition.DiskNumber) Partition $($newWinREPartition.PartitionNumber)", "Set GPT attributes")) {
                        $null = @"
select disk $($newWinREPartition.DiskNumber)
select partition $($newWinREPartition.PartitionNumber)
gpt attributes=0x8000000000000001
exit
"@ | diskpart.exe
                    }
                    Write-Host "Done" -ForegroundColor Green
                }
            }
        }
    }

    Write-Host "Completed Process" -ForegroundColor Green

    Stop-Transcript
}
