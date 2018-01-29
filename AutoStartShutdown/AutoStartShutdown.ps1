<#
Script by Planet Technologies, use of this script is at the user's own discretion. 

#SUMMARY
THe purpose of this runbook is to automatically start and shutdown Azure Resource Manager VMs based on the presence of a tag and on a defined schedule (e.g. 6PM-8AM).
This runbook is designed to be ran in a development/sandbox environment to control the cost of non-production workloads; Use of this runbook on production workloads is not recommended.
#>


<#PARAMETER  
    Parameters are read in from Azure Automation variables.  
    Variables (editable):
    -  StartShutdown_TagName                :  Tag Name for VMs on Start/Shutdown schedule
    -  StartShutdown_TagValue               :  Tag Value for VMs on Start/Shutdown schedule
    -  StartShutdown_SubscriptionName       :  Subscription Name where VMs reside for Start/Shutdown workflow
    -  StartShutdown_AutomationAcct         :  Name of the Automation Acct
    -  StartShutdown_ResourceGroup          :  Name of the Resource Group the Automation Acct resides in

    #>

Param(
    [Parameter(Mandatory=$true,HelpMessage="Enter the desired state, expected values are: Start, Shutdown")]
    [string]
    $DesiredState,
    [Parameter(Mandatory=$true)]
    [bool]$simulate = $false

)

$connectionName = "AzureRunAsConnection"

function ConnectToMAG
{
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName      

    "Logging in to Azure..."
    Add-AzureRmAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint   $servicePrincipalConnection.CertificateThumbprint -environment "AzureUSGovernment"
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
#Select subscription
$Subscriptionname = Get-AutomationVariable -Name "StartShutdown_SubscriptionName"
Select-AzureRmSubscription -SubscriptionName $Subscriptionname
}

#Import tag variables
$TagName = Get-AutomationVariable -Name "StartShutdown_TagName"
$TagValue = Get-AutomationVariable -Name "StartShutdown_TagValue"

function AssertResourceManagerVirtualMachinePowerState
{

    # Get VM with current status
    $resourceManagerVM = Get-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
    $currentStatus = $resourceManagerVM.Statuses | where Code -like "PowerState*" 
    $currentStatus = $currentStatus.Code -replace "PowerState/",""

    # If should be started and isn't, start VM
	if($DesiredState -eq "Start" -and $currentStatus -notmatch "running")
	{
        if($Simulate -eq "True")
        {
            Write-Output "[$($vm.Name)]: SIMULATION -- Would have started VM. (No action taken)"
        }
        else
        {
            Write-Output "[$($vm.Name)]: Starting VM"
            $resourceManagerVM | Start-AzureRmVM
        }
	}
		
	# If should be stopped and isn't, stop VM
	elseif($DesiredState -eq "Shutdown" -and $currentStatus -ne "deallocated")
	{
        if($Simulate -eq "True")
        {
            Write-Output "[$($vm.Name)]: SIMULATION -- Would have stopped VM. (No action taken)"
        }
        else
        {
            Write-Output "[$($vm.Name)]: Stopping VM"
            $resourceManagerVM | Stop-AzureRmVM -Force
        }
	}

    # Otherwise, current power state is correct
    else
    {
        Write-Output "[$($vm.Name)]: Current power state [$currentStatus] is correct."
    }
}

#Start/Shutdown VMs within a tagged resource Group
function AssertRGActionbyTag
{
$vm =@()
$taggedResourceGroups = Find-AzureRmResourceGroup -Tag @{$TagName = $TagValue}
$taggedResourceGroupNames = @($taggedResourceGroups | select -ExpandProperty name)
Write-Output "Found [$($taggedResourceGroupnames.Count)] schedule-tagged resource groups in subscription"	
$vms = foreach ($rgvm in $taggedresourcegroups) {Get-azureRMVM -ResourceGroupName $rgvm.name}
foreach ($vm in $vms) {
AssertResourceManagerVirtualMachinePowerState
}
}


#Start/Shutdown individual VMs with the defined tag
function AssertVmActionByTag
    {
    $vms = Find-AzureRmResource -TagName $TagName -TagValue $TagValue | where {$_.ResourceType -like "Microsoft.Compute/virtualMachines"} 
    Foreach ($vm in $vms){
AssertResourceManagerVirtualMachinePowerState
        }
    }
ConnectToMAG
AssertVmActionByTag
AssertRGActionbyTag

