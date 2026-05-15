#Requires -Version 5.1
<#
.SYNOPSIS
    Installs / removes the ExplorerQuadrant monitor as a Windows logon scheduled task.

.PARAMETER Uninstall
    Remove the scheduled task instead of creating it.
#>
param([switch]$Uninstall)

$TASK_NAME = 'ExplorerQuadrantMonitor'
$SCRIPT    = Join-Path $PSScriptRoot 'ExplorerQuadrant.ps1'

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
        Write-Host "Task '$TASK_NAME' removed."
    } else {
        Write-Host "Task '$TASK_NAME' not found."
    }
    exit
}

if (-not (Test-Path $SCRIPT)) {
    Write-Error "Cannot find ExplorerQuadrant.ps1 at: $SCRIPT"
    exit 1
}

$psArgs = "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""$SCRIPT"""

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 0) -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $TASK_NAME -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Task '$TASK_NAME' registered. It will start automatically at each logon."
Write-Host ""
Write-Host "Start it right now (no reboot needed):"
Write-Host "  Start-ScheduledTask -TaskName '$TASK_NAME'"
Write-Host ""
Write-Host "To remove:"
Write-Host "  .\Install-Startup.ps1 -Uninstall"
