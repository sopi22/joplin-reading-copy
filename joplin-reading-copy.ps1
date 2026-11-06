<#
.SYNOPSIS
  Makes a read-only copy of one Joplin notebook as PDF (or web page) files,
  in a folder you choose, for example a shared Proton Drive folder.

.EXAMPLE
  .\joplin-reading-copy.ps1 -Output "D:\ProtonDrive\My files\Family notes"

.EXAMPLE
  .\joplin-reading-copy.ps1 -Notebook "Family" -Output "D:\Shared\Family notes" -Format html
#>
[CmdletBinding()]
param(
    # The notebook to copy. Its sub-notebooks are copied too. Nothing else is.
    [string]$Notebook = 'Family',
    # Where the reading copy goes.
    [Parameter(Mandatory)][string]$Output,
    # pdf (one PDF per note) or html (web pages with pictures).
    [ValidateSet('pdf', 'html')][string]$Format = 'pdf',
    # Joplin's access key. Normally found automatically.
    [string]$Token,
    [int]$Port = 41184,
    # Remake every file, even ones that didn't change.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'This tool needs PowerShell 7 (free). Install it with:  winget install Microsoft.PowerShell' -ForegroundColor Yellow
    Write-Host 'Then run it with "pwsh" instead of "powershell".'
    exit 2
}
Import-Module (Join-Path $PSScriptRoot 'src\ReadingCopy.psm1') -Force

$IndexName = '00 Start here'
$AttachDir = '_attachments'   # html: every file; pdf: only files that aren't pictures

# ---- 1. Joplin
if (-not (Test-JoplinRunning -Port $Port)) {
    Write-Host "Joplin isn't answering. Open Joplin, and check Tools > Options > Web Clipper > 'Enable Web Clipper Service' is on." -ForegroundColor Yellow
    exit 2
}
$tok = Get-JoplinToken -Token $Token

$folders = @(Invoke-JoplinApi -Path 'folders' -Fields 'id,title,parent_id' -Token $tok -Port $Port -All)
$found = @($folders | Where-Object { $_.title -eq $Notebook })
if ($found.Count -eq 0) { Write-Host "There's no notebook called '$Notebook' in Joplin." -ForegroundColor Yellow; exit 2 }
if ($found.Count -gt 1) {
    $top = @($found | Where-Object { -not $_.parent_id })
    if ($top.Count -ne 1) { Write-Host "More than one notebook is called '$Notebook'. Rename one so the name is unique." -ForegroundColor Yellow; exit 2 }
    $found = $top
}
$root = $found[0]

# Only ids, titles and dates here. Note text is fetched only for shared notes.
$allNotes = Invoke-JoplinApi -Path 'notes' -Fields 'id,title,parent_id,updated_time,is_conflict' -Token $tok -Port $Port -All
$allNotes = @($allNotes | Where-Object { -not $_.is_conflict })
$plan = New-ExportPlan -Folders $folders -Notes $allNotes -RootId $root.id

# ---- 2. What changed since last time
$Output = [IO.Path]::GetFullPath($Output)
$stateDir = Join-Path $env:LOCALAPPDATA 'joplin-reading-copy'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$sha = [Security.Cryptography.SHA1]::Create()
$key = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Output.ToLowerInvariant())) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') })
$stateFile = Join-Path $stateDir "state-$key.json"
$previous = @{}; $prevFiles = @()
if (Test-Path $stateFile) {
    $st = Get-Content $stateFile -Raw | ConvertFrom-Json -AsHashtable
    if ($st.Notes) { $previous = $st.Notes }
    if ($st.Files) { $prevFiles = @($st.Files) }
    if ($st.Format -and $st.Format -ne $Format) { $Force = $true }
}
$changes = Compare-ReadingCopyState -Plan $plan -Previous $previous

# ---- 3. Write
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$stage = Join-Path ([IO.Path]::GetTempPath()) ("jrc-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$edge = if ($Format -eq 'pdf') { Find-Edge } else { $null }
$edgeProfile = Join-Path $stage '_edge'

$noteTargets = @{}
foreach ($p in $plan) {
    $rel = if ($p.Folder) { Join-Path $p.Folder "$($p.BaseName).$Format" } else { "$($p.BaseName).$Format" }
    $noteTargets[$p.Id] = @{ Title = $p.Title; Path = $rel }
}

$newState = @{}; $files = New-Object System.Collections.Generic.HashSet[string]
$written = 0; $kept = 0; $problems = @(); $picCount = 0; $attCount = 0

foreach ($p in $plan) {
    $rel = $noteTargets[$p.Id].Path
    try {
        $resources = @(Invoke-JoplinApi -Path "notes/$($p.Id)/resources" -Fields 'id,title,mime,file_extension,updated_time' -Token $tok -Port $Port -All)
        $resSig = ($resources | Sort-Object id | ForEach-Object { "$($_.id):$($_.updated_time)" }) -join ','

        $resPaths = @{}; $outAttach = @()
        foreach ($r in $resources) {
            $ext = if ($r.file_extension) { ".$($r.file_extension)" } else { '' }
            $nameNoExt = ConvertTo-SafeName ([IO.Path]::GetFileNameWithoutExtension([string]$r.title)) -MaxLength 50
            $fileName = "$($r.id.Substring(0, 8)) $nameNoExt$ext"
            $resPaths[$r.id] = "$AttachDir/$fileName"
            $isPicture = ([string]$r.mime) -like 'image/*'
            if ($isPicture) { $picCount++ } else { $attCount++ }
            if ($Format -eq 'html' -or -not $isPicture) { $outAttach += "$AttachDir\$fileName" }
        }

        $prev = if ($previous.ContainsKey($p.Id)) { $previous[$p.Id] } else { $null }
        $allThere = (Test-Path (Join-Path $Output $rel)) -and -not ($outAttach | Where-Object { -not (Test-Path (Join-Path $Output $_)) })
        $same = $prev -and -not $Force -and ([int64]$prev.UpdatedTime -eq $p.UpdatedTime) -and ($prev.ResSig -eq $resSig) -and ($prev.Path -eq $rel) -and $allThere

        if (-not $same) {
            foreach ($r in $resources) {
                $dest = Join-Path $stage ($resPaths[$r.id] -replace '/', '\')
                if (-not (Test-Path $dest)) {
                    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
                    Invoke-JoplinApi -Path "resources/$($r.id)/file" -Token $tok -Port $Port -OutFile $dest
                }
            }
            $note = Invoke-JoplinApi -Path "notes/$($p.Id)" -Fields 'body' -Token $tok -Port $Port
            $md = Convert-JoplinLinks -Markdown ([string]$note.body) -NoteTargets $noteTargets -ResourcePaths $resPaths -FromFolder $p.Folder -Mode $Format
            $html = New-NoteHtml -Title $p.Title -BodyHtml (ConvertFrom-Markdown -InputObject $md).Html -UpdatedTime $p.UpdatedTime

            $stageHtml = Join-Path $stage ([IO.Path]::ChangeExtension($rel, 'html'))
            New-Item -ItemType Directory -Path (Split-Path $stageHtml) -Force | Out-Null
            Set-Content -Path $stageHtml -Value $html -Encoding utf8
            $target = Join-Path $Output $rel
            New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
            if ($Format -eq 'pdf') {
                $stagePdf = [IO.Path]::ChangeExtension($stageHtml, 'pdf')
                ConvertTo-Pdf -HtmlPath $stageHtml -PdfPath $stagePdf -EdgePath $edge -ProfileDir $edgeProfile
                Move-Item $stagePdf $target -Force
            } else {
                Copy-Item $stageHtml $target -Force
            }
            foreach ($a in $outAttach) {
                $dest = Join-Path $Output $a
                New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
                Copy-Item (Join-Path $stage $a) $dest -Force
            }
            $written++
        } else { $kept++ }

        [void]$files.Add($rel); foreach ($a in $outAttach) { [void]$files.Add($a) }
        $newState[$p.Id] = @{ UpdatedTime = $p.UpdatedTime; Title = $p.Title; ResSig = $resSig; Path = $rel }
    } catch {
        $problems += "Note $($plan.IndexOf($p) + 1) of $($plan.Count): $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber) in $(Split-Path -Leaf $_.InvocationInfo.ScriptName))"
        if ($prev) { $newState[$p.Id] = $prev; [void]$files.Add($rel) }   # keep the old copy
    }
}

# ---- 4. Start page (only remade when something changed)
$indexRel = "$IndexName.$Format"
[void]$files.Add($indexRel)
$somethingChanged = $Force -or $written -gt 0 -or @($changes.Removed).Count -gt 0 -or -not (Test-Path (Join-Path $Output $indexRel))
if ($somethingChanged) {
    $indexMd = New-IndexMarkdown -NotebookTitle $root.title -Plan $plan -Changes $changes -Extension $Format
    $indexHtml = New-NoteHtml -Title $root.title -BodyHtml (ConvertFrom-Markdown -InputObject $indexMd).Html -IsIndex
    $stageIndex = Join-Path $stage "$IndexName.html"
    Set-Content -Path $stageIndex -Value $indexHtml -Encoding utf8
    if ($Format -eq 'pdf') {
        ConvertTo-Pdf -HtmlPath $stageIndex -PdfPath (Join-Path $stage "$IndexName.pdf") -EdgePath $edge -ProfileDir $edgeProfile
        Move-Item (Join-Path $stage "$IndexName.pdf") (Join-Path $Output $indexRel) -Force
    } else {
        Copy-Item $stageIndex (Join-Path $Output $indexRel) -Force
    }
}

# ---- 5. Remove files this tool made earlier that are no longer needed.
#         Files it didn't make are never touched.
$removedFiles = 0
foreach ($f in $prevFiles) {
    if ($files.Contains($f)) { continue }
    $full = Join-Path $Output $f
    if (Test-Path $full -PathType Leaf) { Remove-Item $full -Force; $removedFiles++ }
    $dir = Split-Path $full
    while ($dir.Length -gt $Output.Length -and (Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) {
        Remove-Item $dir -Force; $dir = Split-Path $dir
    }
}

@{ Format = $Format; Notes = $newState; Files = @($files) } | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding utf8
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

# ---- 6. Report (counts only, never note text)
Write-Host ''
Write-Host "Reading copy of '$($root.title)' -> $Output"
Write-Host ("  {0} notes: {1} new, {2} updated, {3} removed since last time" -f $plan.Count, @($changes.New).Count, @($changes.Changed).Count, @($changes.Removed).Count)
Write-Host ("  {0} files made, {1} unchanged (left as they were), {2} old files removed" -f $written, $kept, $removedFiles)
Write-Host ("  {0} pictures, {1} attachments" -f $picCount, $attCount)
if ($problems) {
    Write-Host "  Problems ($($problems.Count)):" -ForegroundColor Yellow
    $problems | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    exit 1
}
Write-Host '  All done.' -ForegroundColor Green
