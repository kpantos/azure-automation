# Set variables
$subscriptionId = ""
$resourceGroup = ""
$vmName = ""
$location = "northeurope"
$zone = "1"


# Login to Azure
Connect-AzAccount
Select-AzSubscription -Subscriptionid $subscriptionId

# Get the details of the VM to be moved to the Availability Set
$originalVM = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName

# Stop the VM to take snapshot
Stop-AzVM -ResourceGroupName $resourceGroup -Name $vmName

# Create a SnapShot of the OS disk and then, create an Azure Disk with Zone information
$snapshotOSConfig = New-AzSnapshotConfig -SourceUri $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy -SkuName Standard_ZRS
$OSSnapshot = New-AzSnapshot -Snapshot $snapshotOSConfig -SnapshotName ($originalVM.StorageProfile.OsDisk.Name + "-snapshot") -ResourceGroupName $resourceGroup 

$diskConfig = New-AzDiskConfig -Location $OSSnapshot.Location -SourceResourceId $OSSnapshot.Id -CreateOption Copy -SkuName Premium_LRS -Zone $zone
$OSdisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName ($originalVM.StorageProfile.OsDisk.Name + "zone")


# Create a Snapshot from the Data Disks and the Azure Disks with Zone information
foreach ($disk in $originalVM.StorageProfile.DataDisks) { 

   $snapshotDataConfig = New-AzSnapshotConfig -SourceUri $disk.ManagedDisk.Id -Location $location -CreateOption copy -SkuName Standard_ZRS
   $DataSnapshot = New-AzSnapshot -Snapshot $snapshotDataConfig -SnapshotName ($disk.Name + '-snapshot') -ResourceGroupName $resourceGroup

   $datadiskConfig = New-AzDiskConfig -Location $DataSnapshot.Location -SourceResourceId $DataSnapshot.Id -CreateOption Copy -SkuName Premium_LRS -Zone $zone
   $datadisk = New-AzDisk -Disk $datadiskConfig -ResourceGroupName $resourceGroup -DiskName ($disk.Name + "zone")
}

# Remove the original VM
Remove-AzVM -ResourceGroupName $resourceGroup -Name $vmName  

# Create the basic configuration for the replacement VM
$newVM = New-AzVMConfig -VMName $originalVM.Name -VMSize $originalVM.HardwareProfile.VmSize -Zone $zone

# Add the pre-existed OS disk 
Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $OSdisk.Id -Name $OSdisk.Name -Windows

# Add the pre-existed data disks
foreach ($disk in $originalVM.StorageProfile.DataDisks) { 
    $datadisk = Get-AzDisk -ResourceGroupName $resourceGroup -DiskName ($disk.Name + "zone")
    Add-AzVMDataDisk -VM $newVM -Name $datadisk.Name -ManagedDiskId $datadisk.Id -Caching $disk.Caching -Lun $disk.Lun -DiskSizeInGB $disk.DiskSizeGB -CreateOption Attach 
}

# Add NIC(s) and keep the same NIC as primary
foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {	
if ($nic.Primary -eq "True")
   {
      Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id -Primary
   }
   else
   {
      Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id 
   }
}

# Recreate the VM
New-AzVM -ResourceGroupName $resourceGroup -Location $originalVM.Location -VM $newVM -DisableBginfoExtension