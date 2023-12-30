Start-Transcript -Append

#get Disk Layouts
#check WinRE partition
#Check avialble Space
#capture Partition
#remove WinRE
#Extend and Shirnk System
#Create partition
#restore Partiion
#HidePartition

Write-host "Starting Process" -ForegroundColor White
Write-host "-Gathering Disk Configs" -NoNewline -ForegroundColor White

$disk = Get-Disk | where-object {$_.IsBoot -eq $true}

if($disk -eq $null)
{
    Write-Host "*** Error Selecting Disks ***" -ForegroundColor Red
    Stop-Transcript
    exit
}
else
{
    Write-Host " +Found Boot Disk" -ForegroundColor Green
}

$currentSize = $disk.size / 1024 /1024 /1024
$allocatedSize = $disk.AllocatedSize /1024 /1024 /1024
write-host " Current Disk Size: $($currentSize)GB"
write-host " Current Allocated Size: $($allocatedSize)GB"

if($currentSize - $allocatedSize -le 1)
{
    write-host " Not enough Free Space on Disk. Expecting over 1GB Free Exiting.." -ForegroundColor Red
    Stop-Transcript
    exit
}
else
{
    write-host " - Checking Partitions Order" -ForegroundColor Yellow


    $partitions = Get-Partition -disk $disk

    write-host "   Number of Partitions Found: $($partitions.count)" -ForegroundColor Green
    write-host " - Finding Recovery Partitions - " -NoNewline -ForegroundColor Yellow
    $winrePartition = $partitions | where-object {$_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'}
    if($winrePartition -eq $null)
    {
        Write-host "No WinRE Partitions Found. Exiting... " -ForegroundColor Red
        Stop-Transcript
        exit
    }
    else
    {
        Write-host "WinRE Partition Found!" -ForegroundColor Green
        Write-Host " - Evaluating WinRE Partition - " -nonewline -ForegroundColor Yellow
        if ($partitions.count -ne $winrePartition.PartitionNumber)
        {
            write-host "Not Last Partition. Aborting" -ForegroundColor Red
            Stop-Transcript
            exit

        }
        else
        {
            write-host "Confirmed Partition is last current partition" -ForegroundColor Green
            write-host " - Checking for WinRE TempPath - " -NoNewline -ForegroundColor Yellow
            If(test-path -Path "C:\windows\temp\winre")
            {
                write-host "Path Exists!" -ForegroundColor Cyan
                write-host " - Checking for already mapped partitions - " -NoNewline -ForegroundColor Yellow
                #check for already mapped
                write-host " Oh well Check Next time" -ForegroundColor Green
            }
            else
            {
                Write-Host "Path does not exist." -ForegroundColor Green
                write-host " - Creating Temp Path for WinRE - " -ForegroundColor Yellow -NoNewline
                new-item -Path "c:\windows\temp\winre" -ItemType Directory | out-null
                write-host "Created Path" -ForegroundColor Green
            }

            write-host " - Mapping WinRE Partition to Temp Path - " -ForegroundColor Yellow -NoNewline

            Add-PartitionAccessPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -AccessPath c:\windows\temp\winre

            write-host "Mapped WinRE to temp path" -ForegroundColor Green
            #Checking Partition for content

            #prompt to proceed

            Write-host " - Checking WinRE Partition - " -NoNewline -ForegroundColor Yellow
            if (test-path -Path "C:\windows\temp\winre\Recovery\WindowsRE\Winre.wim")
            {
                Write-Host "Found the WinRE WIM file and will proceed" -ForegroundColor Green
            }
            else
            {
                write-host "Not sure on the WinRE partition so aborting" -ForegroundColor Red
                write-host " - Cleaning Up" -ForegroundColor Red
                write-host "   - Removing Mapping" -ForegroundColor Red
                Remove-PartitionAccessPath -AccessPath "c:\windows\temp\winre" -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                Write-host "Ending Process" -ForegroundColor Red
                Stop-Transcript
                exit
            }
            Write-Host " - Creating new partition - " -NoNewline -ForegroundColor Yellow
            $Partitionoffset = $disk.Size - ($winrePartition.Size + (1 *1024 *1024))
            $newWinREPartition = New-Partition -Offset $partitionOffset -Size $winrePartition.Size -DiskNumber $winrePartition.DiskNumber -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
            Write-Host "Done" -ForegroundColor Green
           
            Write-Host " - Formatting new partition - " -NoNewline -ForegroundColor Yellow
            Get-Volume -Partition $newWinREPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel Recovery  | out-null
            Write-Host "Done" -ForegroundColor Green
            
            Write-host " - Checking Temp Path for New WinRE - " -ForegroundColor Yellow -NoNewline
            If(test-path -Path "C:\windows\temp\winreNew")
            {
                write-host "Path Exists! Checking for already mapped partitions" -ForegroundColor Cyan
                #check for already mapped

            }
            else
            {
                Write-Host "Path does not exist." -ForegroundColor Green
                write-host " - Creating Temp Path for New WinRE - " -ForegroundColor Yellow -NoNewline
                new-item -Path "c:\windows\temp\winreNew" -ItemType Directory  | out-null
                write-host "Done" -ForegroundColor Green
            }

            write-host " - Adding access Path to New WinRE - " -ForegroundColor Yellow -NoNewline
            Add-PartitionAccessPath -AccessPath "C:\windows\temp\winreNew" -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber            
            Write-host "Done!" -ForegroundColor Green            
            
            write-host " - Copying Data - " -ForegroundColor Yellow -NoNewline
            Copy-Item -Path C:\windows\temp\winre\Recovery -Destination C:\Windows\Temp\winrenew -Container -Recurse
            write-host "Done" -ForegroundColor Green
            
            Write-host "Disconnecting Mapped Access Paths" -ForegroundColor White
            
            write-host " - Removing Mapping for New Recovery Partition - " -NoNewline -ForegroundColor Yellow
            Remove-PartitionAccessPath -AccessPath "C:\windows\temp\winreNew" -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
            write-host "Done" -ForegroundColor Green
            
            write-host " - Removing Mapping for Old Recovery Partition - " -NoNewline -ForegroundColor Yellow          
            Remove-PartitionAccessPath -AccessPath "c:\windows\temp\winre" -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
            Write-host " Done!" -ForegroundColor Green

            Write-host "Fixing Recovery Partitions and Settings" -ForegroundColor White

            write-host " - Disabling Recovery Partition - " -ForegroundColor Yellow
            C:\windows\system32\ReAgentc.exe /disable
            write-host "Done" -ForegroundColor Green

            write-host " - Removing old Recovery Partition - " -NoNewline -ForegroundColor Yellow
            Remove-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -Confirm:$false
            write-host "Done" -ForegroundColor Green

            write-host " - Setting Recovery Partition Path - " -ForegroundColor Yellow
            $winrepathset = "\\?\GLOBALROOT\device\harddisk$($newWinREPartition.DiskNumber)\partition$($newWinREPartition.PartitionNumber)\Recovery\WindowsRE"
            C:\Windows\System32\ReAgentc.exe /setreimage /path $winrepathset /target c:\Windows
            write-host "Done" -ForegroundColor Green

            write-host " - Enabling Recovery Partition - " -ForegroundColor Yellow
            C:\Windows\System32\ReAgentc.exe /enable
            write-host "Done" -ForegroundColor Green

            Write-host "Fixing Partitions" -ForegroundColor White

            write-host " - Resizing Partition Before New Recovery Partition - " -NoNewline -ForegroundColor Yellow
            $size = (Get-PartitionSupportedSize -DiskNumber $winrePartition.DiskNumber -PartitionNumber ($winrePartition.PartitionNumber - 1))
            Resize-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber ($winrePartition.PartitionNumber - 1) -Size $size.SizeMax
            write-host "Done" -ForegroundColor Green

            write-host " - Setting Attributes on Recovery Partition - " -NoNewline -ForegroundColor Yellow
            $null = @"
select disk $($newWinREPartition.DiskNumber)
select partition $($newWinREPartition.PartitionNumber)
gpt attributes=0x8000000000000001
exit
"@ | diskpart.exe
            write-host "Done" -ForegroundColor Green
        }
    }
}








Write-host "Completed Process" -ForegroundColor Green

Stop-Transcript
