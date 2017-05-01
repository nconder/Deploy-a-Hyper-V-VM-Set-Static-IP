
$csvfile = "C:\servers.csv"
$servers = Import-CSV $csvfile -Header vmname,vmcsv,vmipaddrfn,vmsubnetfn,vmgatewayfn,vmdnsfn,vmdnsfn2 

forEach ($item in $servers){

$vmname = $item.vmname
$vmcsv = $item.vmcsv
$vmipaddrfn = $item.vmipaddrfn
$vmsubnetfn = $item.vmsubnetfn
$vmgatewayfn = $item.vmgatewayfn
$vmdnsfn = $item.vmdnsfn
$clusterpath = ('C:\ClusterStorage\') + $vmcsv + ("\") + $vmname
$VhdDestinationPath = ('C:\ClusterStorage\') + $vmcsv  + ('\') + $vmname + ('\Virtual Hard Disks')
# Display vars
$vmname
$vmcsv
$vmipaddrfn
$vmsubnetfn
$vmgatewayfn
$vmdnsfn
$vmdnsfn2
$clusterpath
$VhdDestinationPath

New-Item $clusterpath -type directory
New-Item ($clusterpath + "\Virtual Hard Disks") -type directory 
Start-Sleep -s 2
$vmconfig = Get-Item 'C:\ClusterStorage\CSV01\LABW2K12R2TPLT_DEPLOY\Virtual Machines\*.xml' | select -ExpandProperty Fullname

# Importing New VM
Write-Host "Importing New VM..." -ForegroundColor Green
Import-VM -Path $vmconfig -copy -GenerateNewId -SmartPagingFilePath $clusterpath -SnapshotFilePath $clusterpath -VirtualMachinePath $clusterpath -VhdDestinationPath $VhdDestinationPath

# Update VM Name
Write-Host "Updating VM Name..." -ForegroundColor Green
Rename-VM LABW2K12R2TPLT –NewName $vmname

# Power On New VM
Write-Host "Powering On New VM..." -ForegroundColor Green
Start-VM –Name $vmname

# Configure VM As Highly Available
Write-Host "Configuring VM as Highly Available..." -ForegroundColor Green
Add-ClusterVirtualMachineRole -VirtualMachine $vmname

# Sets static ip on VM
Function Set-VMNetworkConfiguration {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
                   Position=1,
                   ParameterSetName='DHCP',
                   ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName='Static',
                   ValueFromPipeline=$true)]
        [Microsoft.HyperV.PowerShell.VMNetworkAdapter]$NetworkAdapter,

        [Parameter(Mandatory=$true,
                   Position=1,
                   ParameterSetName='Static')]
        [String[]]$IPAddress=@(),

        [Parameter(Mandatory=$false,
                   Position=2,
                   ParameterSetName='Static')]
        [String[]]$Subnet=@(),

        [Parameter(Mandatory=$false,
                   Position=3,
                   ParameterSetName='Static')]
        [String[]]$DefaultGateway = @(),

        [Parameter(Mandatory=$false,
                   Position=4,
                   ParameterSetName='Static')]
        [String[]]$DNSServer = @(),

        [Parameter(Mandatory=$false,
                   Position=0,
                   ParameterSetName='DHCP')]
        [Switch]$Dhcp
    )

    $VM = Get-WmiObject -Namespace 'root\virtualization\v2' -Class 'Msvm_ComputerSystem' | Where-Object { $_.ElementName -eq $NetworkAdapter.VMName } 
    $VMSettings = $vm.GetRelated('Msvm_VirtualSystemSettingData') | Where-Object { $_.VirtualSystemType -eq 'Microsoft:Hyper-V:System:Realized' }    
    $VMNetAdapters = $VMSettings.GetRelated('Msvm_SyntheticEthernetPortSettingData') 

    $NetworkSettings = @()
    foreach ($NetAdapter in $VMNetAdapters) {
        if ($NetAdapter.Address -eq $NetworkAdapter.MacAddress) {
            $NetworkSettings = $NetworkSettings + $NetAdapter.GetRelated("Msvm_GuestNetworkAdapterConfiguration")
        }
    }

    $NetworkSettings[0].IPAddresses = $IPAddress
    $NetworkSettings[0].Subnets = $Subnet
    $NetworkSettings[0].DefaultGateways = $DefaultGateway
    $NetworkSettings[0].DNSServers = $DNSServer
    $NetworkSettings[0].ProtocolIFType = 4096

    if ($dhcp) {
        $NetworkSettings[0].DHCPEnabled = $true
    } else {
        $NetworkSettings[0].DHCPEnabled = $false
    }

    $Service = Get-WmiObject -Class "Msvm_VirtualSystemManagementService" -Namespace "root\virtualization\v2"
    $setIP = $Service.SetGuestNetworkAdapterConfiguration($VM, $NetworkSettings[0].GetText(1))

    if ($setip.ReturnValue -eq 4096) {
        $job=[WMI]$setip.job 

        while ($job.JobState -eq 3 -or $job.JobState -eq 4) {
            start-sleep 1
            $job=[WMI]$setip.job
        }

        if ($job.JobState -eq 7) {
            write-host "Success"
        }
        else {
            $job.GetError()
        }
    } elseif($setip.ReturnValue -eq 0) {
        Write-Host "Success"
    }
}
# Gets VM info
Function Get-VMNetworkConfiguration {
    [CmdletBinding()]

    Param (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$True,
                   ParametersetName='VMName',
                   Position=0)]
        [ValidateScript({
            Get-VM -Name $_
        }
        )]
        [String]$VMName   
    )

    $vmObject = Get-WmiObject -Namespace 'root\virtualization\v2' -Class 'Msvm_ComputerSystem' | Where-Object { $_.ElementName -eq $vmName }

    if ($vmObject.EnabledState -ne 2) {
        Write-Error "${vmName} is not in running state; The network configuration data won't be available"
    } else {
        $vmSetting = $vmObject.GetRelated('Msvm_VirtualSystemSettingData') | Where-Object { $_.VirtualSystemType -eq 'Microsoft:Hyper-V:System:Realized' } 
        $netAdapter = $vmSetting.GetRelated('Msvm_SyntheticEthernetPortSettingData')
        foreach($Adapter in $netAdapter) { 
            $Adapter.GetRelated("Msvm_GuestNetworkAdapterConfiguration") | Select IPAddresses, Subnets, DefaultGateways, DNSServers, DHCPEnabled, @{Name="AdapterName";Expression={$Adapter.ElementName}}
        }
    }
}

Start-Sleep -s 8
(Get-VMNetworkAdapter -VMName $vmName)[0] | Set-VMNetworkConfiguration -DHCP
Start-Sleep -s 4
(Get-VMNetworkAdapter -VMName $vmName)[0] | Set-VMNetworkConfiguration -IPAddress $vmipaddrfn -Subnet $vmsubnetfn -DNSServer $vmdnsfn, $vmdnsfn2 -DefaultGateway $vmgatewayfn


}
