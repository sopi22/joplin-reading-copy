<#
Runs joplin-reading-copy and saves what happened to a log file.
Windows Task Scheduler starts this every day (see register-daily-task.ps1).

Log of the last run: %LOCALAPPDATA%\joplin-reading-copy\last-run.txt
#>
param(
    [Parameter(Mandatory)] [string] $Output,
    [string] $Notebook = 'Family'
)

$log = Join-Path $env:LOCALAPPDATA 'joplin-reading-copy\last-run.txt'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
"Run started $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Set-Content $log -Encoding utf8

$tool = Join-Path (Split-Path $PSScriptRoot) 'joplin-reading-copy.ps1'
& $tool -Notebook $Notebook -Output $Output *>> $log

$code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
"Exit code $code (0 = OK, 1 = some notes had problems, 2 = Joplin was closed)" | Add-Content $log -Encoding utf8
exit $code
