function Move-WinRE {
    <#
    .SYNOPSIS
    Moves a Windows RE Partition to the end of the disk

    .DESCRIPTION
    Desc

    .EXAMPLE
    PS C:\> Move-WinRE
#>
    [CmdletBinding()]
    param (
        # [Parameter()]
        # [bool]
        # $NoPrompt = $false
    )
Start-Transcript -Append

$licenseText = @"
Move-WinPE.PS1 - Used to move a windows recovery partition to the end of an expanded disk and expand the preceeding partition.
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
Write-Output $licenseText
write-output ""
$response = Read-Host -Prompt "Press 'y' to continue or any other key to abort"
if ($response -ne 'y') {
    Write-Output "Aborted."
    exit
}
write-output ""
Write-Output "Starting Process" -ForegroundColor White
Write-Output "-Gathering Disk Configs" -NoNewline -ForegroundColor White

$disk = Get-Disk | where-object {$_.IsBoot -eq $true}

if($null -eq $disk)
{
    Write-Output "*** Error Selecting Disks ***" -ForegroundColor Red
    Stop-Transcript
    exit
}
else
{
    Write-Output " +Found Boot Disk" -ForegroundColor Green
}

$currentSize = $disk.size / 1024 /1024 /1024
$allocatedSize = $disk.AllocatedSize /1024 /1024 /1024
Write-Output " Current Disk Size: $($currentSize)GB"
Write-Output " Current Allocated Size: $($allocatedSize)GB"

if($currentSize - $allocatedSize -le 1)
{
    Write-Output " Not enough Free Space on Disk. Expecting over 1GB Free Exiting.." -ForegroundColor Red
    Stop-Transcript
    exit
}
else
{
    Write-Output " - Checking Partitions Order" -ForegroundColor Yellow


    $partitions = Get-Partition -disk $disk

    Write-Output "   Number of Partitions Found: $($partitions.count)" -ForegroundColor Green
    Write-Output " - Finding Recovery Partitions - " -NoNewline -ForegroundColor Yellow
    $winrePartition = $partitions | where-object {$_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'}
    if($null -eq $winrePartition)
    {
        Write-Output "No WinRE Partitions Found. Exiting... " -ForegroundColor Red
        Stop-Transcript
        exit
    }
    else
    {
        Write-Output "WinRE Partition Found!" -ForegroundColor Green
        Write-Output " - Evaluating WinRE Partition - " -nonewline -ForegroundColor Yellow
        if ($partitions.count -ne $winrePartition.PartitionNumber)
        {
            Write-Output "Not Last Partition. Aborting" -ForegroundColor Red
            Stop-Transcript
            exit

        }
        else
        {
            Write-Output "Confirmed Partition is last current partition" -ForegroundColor Green
            Write-Output " - Checking for WinRE TempPath - " -NoNewline -ForegroundColor Yellow
            If(test-path -Path "C:\windows\temp\winre")
            {
                Write-Output "Path Exists!" -ForegroundColor Cyan
                Write-Output " - Checking for already mapped partitions - " -NoNewline -ForegroundColor Yellow
                #check for already mapped
                Write-Output " Oh well Check Next time" -ForegroundColor Green
            }
            else
            {
                Write-Output "Path does not exist." -ForegroundColor Green
                Write-Output " - Creating Temp Path for WinRE - " -ForegroundColor Yellow -NoNewline
                new-item -Path "c:\windows\temp\winre" -ItemType Directory | out-null
                Write-Output "Created Path" -ForegroundColor Green
            }

            Write-Output " - Mapping WinRE Partition to Temp Path - " -ForegroundColor Yellow -NoNewline

            Add-PartitionAccessPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -AccessPath c:\windows\temp\winre

            Write-Output "Mapped WinRE to temp path" -ForegroundColor Green
            #Checking Partition for content

            #prompt to proceed

            Write-Output " - Checking WinRE Partition - " -NoNewline -ForegroundColor Yellow
            if (test-path -Path "C:\windows\temp\winre\Recovery\WindowsRE\Winre.wim")
            {
                Write-Output "Found the WinRE WIM file and will proceed" -ForegroundColor Green
            }
            else
            {
                Write-Output "Not sure on the WinRE partition so aborting" -ForegroundColor Red
                Write-Output " - Cleaning Up" -ForegroundColor Red
                Write-Output "   - Removing Mapping" -ForegroundColor Red
                Remove-PartitionAccessPath -AccessPath "c:\windows\temp\winre" -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                Write-Output "Ending Process" -ForegroundColor Red
                Stop-Transcript
                exit
            }
            Write-Output " - Creating new partition - " -NoNewline -ForegroundColor Yellow
            $Partitionoffset = $disk.Size - ($winrePartition.Size + (1 *1024 *1024))
            $newWinREPartition = New-Partition -Offset $partitionOffset -Size $winrePartition.Size -DiskNumber $winrePartition.DiskNumber -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
            Write-Output "Done" -ForegroundColor Green

            Write-Output " - Formatting new partition - " -NoNewline -ForegroundColor Yellow
            Get-Volume -Partition $newWinREPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel Recovery  | out-null
            Write-Output "Done" -ForegroundColor Green

            Write-Output " - Checking Temp Path for New WinRE - " -ForegroundColor Yellow -NoNewline
            If(test-path -Path "C:\windows\temp\winreNew")
            {
                Write-Output "Path Exists! Checking for already mapped partitions" -ForegroundColor Cyan
                #check for already mapped
            }
            else
            {
                Write-Output "Path does not exist." -ForegroundColor Green
                Write-Output " - Creating Temp Path for New WinRE - " -ForegroundColor Yellow -NoNewline
                new-item -Path "c:\windows\temp\winreNew" -ItemType Directory  | out-null
                Write-Output "Done" -ForegroundColor Green
            }
            Write-Output " - Adding access Path to New WinRE - " -ForegroundColor Yellow -NoNewline
            Add-PartitionAccessPath -AccessPath "C:\windows\temp\winreNew" -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
            Write-Output "Done!" -ForegroundColor Green
            Write-Output " - Copying Data - " -ForegroundColor Yellow -NoNewline
            Copy-Item -Path C:\windows\temp\winre\Recovery -Destination C:\Windows\Temp\winrenew -Container -Recurse
            Write-Output "Done" -ForegroundColor Green
            Write-Output "Disconnecting Mapped Access Paths" -ForegroundColor White
            Write-Output " - Removing Mapping for New Recovery Partition - " -NoNewline -ForegroundColor Yellow
            Remove-PartitionAccessPath -AccessPath "C:\windows\temp\winreNew" -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
            Write-Output "Done" -ForegroundColor Green
            Write-Output " - Removing Mapping for Old Recovery Partition - " -NoNewline -ForegroundColor Yellow
            Remove-PartitionAccessPath -AccessPath "c:\windows\temp\winre" -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
            Write-Output " Done!" -ForegroundColor Green

            Write-Output "Fixing Recovery Partitions and Settings" -ForegroundColor White

            Write-Output " - Disabling Recovery Partition - " -ForegroundColor Yellow
            C:\windows\system32\ReAgentc.exe /disable
            Write-Output "Done" -ForegroundColor Green

            Write-Output " - Removing old Recovery Partition - " -NoNewline -ForegroundColor Yellow
            Remove-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -Confirm:$false
            Write-Output "Done" -ForegroundColor Green

            Write-Output " - Setting Recovery Partition Path - " -ForegroundColor Yellow
            $winrepathset = "\\?\GLOBALROOT\device\harddisk$($newWinREPartition.DiskNumber)\partition$($newWinREPartition.PartitionNumber)\Recovery\WindowsRE"
            C:\Windows\System32\ReAgentc.exe /setreimage /path $winrepathset /target c:\Windows
            Write-Output "Done" -ForegroundColor Green

            Write-Output " - Enabling Recovery Partition - " -ForegroundColor Yellow
            C:\Windows\System32\ReAgentc.exe /enable
            Write-Output "Done" -ForegroundColor Green

            Write-Output "Fixing Partitions" -ForegroundColor White

            Write-Output " - Resizing Partition Before New Recovery Partition - " -NoNewline -ForegroundColor Yellow
            $size = (Get-PartitionSupportedSize -DiskNumber $winrePartition.DiskNumber -PartitionNumber ($winrePartition.PartitionNumber - 1))
            Resize-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber ($winrePartition.PartitionNumber - 1) -Size $size.SizeMax
            Write-Output "Done" -ForegroundColor Green

            Write-Output " - Setting Attributes on Recovery Partition - " -NoNewline -ForegroundColor Yellow
            $null = @"
select disk $($newWinREPartition.DiskNumber)
select partition $($newWinREPartition.PartitionNumber)
gpt attributes=0x8000000000000001
exit
"@ | diskpart.exe
            Write-Output "Done" -ForegroundColor Green
        }
    }
}








Write-Output "Completed Process" -ForegroundColor Green

Stop-Transcript
}