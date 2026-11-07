<#
Makes a Windows scheduled task that updates the reading copy every day,
then runs it once right away as a test.

Run it once in a normal PowerShell window (no admin needed):
  powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Tools\joplin-reading-copy\schedule\register-daily-task.ps1" -Output "D:\ProtonDrive\My files\Family notes"

Running it again is safe: it replaces the old task (use this to change the time).
#>
param(
    [Parameter(Mandatory)] [string] $Output,
    [string] $Notebook = 'Family',
    [string] $At = '9pm',
    [string] $TaskName = 'Family notes copy (Joplin to Proton)'
)

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$runner = Join-Path $PSScriptRoot 'run-daily.ps1'
$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runner`" -Output `"$Output`" -Notebook `"$Notebook`""

$action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Daily -At $At
# StartWhenAvailable: if the computer was off at that time, run as soon as it's on again.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Copies the Joplin notebook '$Notebook' to $Output (joplin-reading-copy)" -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "Task '$TaskName' created and started once as a test. It runs every day at $At from now on."
Write-Host "Check the result in a minute: Get-Content `"$env:LOCALAPPDATA\joplin-reading-copy\last-run.txt`""
