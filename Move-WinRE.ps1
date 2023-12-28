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

$disk = Get-Disk | where-object {$_.IsBoot -eq $true}

if($disk -eq $null)
{
    Write-Host "Error Selecting Disks"
    Stop-Transcript
    exit
}
else
{
    Write-Host " Found Boot Disk. Checking Partitions"
}
$currentSize = $disk.size / 1024 /1024 /1024
$allocatedSize = $disk.AllocatedSize /1024 /1024 /1024
write-host " Current Disk Size: $($currentSize)GB"
write-host " Current Allocated Size: $($allocatedSize)GB"

if($currentSize - $allocatedSize -le 0.5)
{
    write-host " Not enough Free Space on Disk. Expecting 500MB Exiting.."
    Stop-Transcript
    exit
}
else
{
    write-host " Checking Partitions Order"


    $partitions = Get-Partition -disk $disk

    write-host "Number of Partiions Found: $($partitions.count)"
    $partitions

    write-host ""
    write-host " Finding Recovery Partitions"
    $winrePartition = $partitions | where-object {$_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'}
    if($winrePartition -eq $null)
    {
        Write-host "No WinRE Partitions Found. Exiting... "
        Stop-Transcript
        exit
    }
    else
    {
        Write-host "WinRE Partition Found! Evaluating...."
        if ($partitions.count -ne $winrePartition.PartitionNumber)
        {
            write-host "Not Last Partition. Aborting"
            Stop-Transcript
            exit

        }
        else
        {
            write-host "Confirmed Partion is last and free space"
            #check C:\windows\temp\winre
            If(test-path -Path "C:\windows\temp\winre")
            {
                write-host " Path Exists! Checking for already mapped partitions"
                #check for already mapped

            }
            else
            {
                Write-Host "Path does not exist. Creating"
                new-item -Path "c:\windows\temp\winre" -ItemType Directory
                write-host "Created Path"
            }



            Add-PartitionAccessPath -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -AccessPath c:\windows\temp\winre

            #Checking Partition for content

            #prompt to proceed

            Write-host "Cehcking WinRE Partition:"
            if (test-path -Path "C:\windows\temp\winre\Recovery\WindowsRE\Winre.wim")
            {
                Write-Host "Found the WinRE WIM file and will proceed"
            }
            else
            {
                write-host "Not sure on the WinRE partition so aborting"
                Remove-PartitionAccessPath -AccessPath "c:\windows\temp\winre" -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber
                Stop-Transcript
                exit
            }

            $Partitionoffset = $disk.Size - ($winrePartition.Size + (1 *1024 *1024))
            $newWinREPartition = New-Partition -Offset $partitionOffset -Size $winrePartition.Size -DiskNumber $winrePartition.DiskNumber -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
           

            Get-Volume -Partition $newWinREPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel Recovery 
           
            If(test-path -Path "C:\windows\temp\winreNew")
            {
                write-host " Path Exists! Checking for already mapped partitions"
                #check for already mapped

            }
            else
            {
                Write-Host "Path does not exist. Creating"
                new-item -Path "c:\windows\temp\winreNew" -ItemType Directory
                write-host "Created Path"
            }


            Add-PartitionAccessPath -AccessPath "C:\windows\temp\winreNew" -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
            write-host "Copying Data"
            Copy-Item -Path C:\windows\temp\winre\Recovery -Destination C:\Windows\Temp\winrenew -Container -Recurse
            write-host "Copy Finished"
            #remove Access Path
            Write-host "Disconnecting maps" -NoNewline
            Remove-PartitionAccessPath -AccessPath "C:\windows\temp\winreNew" -DiskNumber $newWinREPartition.DiskNumber -PartitionNumber $newWinREPartition.PartitionNumber
            
            Remove-PartitionAccessPath -AccessPath "c:\windows\temp\winre" -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber

            Write-host " Done!"
            C:\windows\system32\ReAgentc.exe /disable
            Remove-Partition -DiskNumber $winrePartition.DiskNumber -PartitionNumber $winrePartition.PartitionNumber -Confirm:$false
            C:\Windows\System32\ReAgentc.exe /setreimage /path \\?\GLOBALROOT\device\harddisk0\partition5\Recovery\WindowsRE /target c:\Windows
            C:\Windows\System32\ReAgentc.exe /enable
        }
    }
}








Write-host "Completed Process"

Stop-Transcript
