# ReadingCopy.psm1
# Logic for joplin-reading-copy. The functions near the top are "pure"
# (no network, no files) so they can be tested with fake notes. The
# functions at the bottom talk to Joplin, Edge and the disk.

Set-StrictMode -Version Latest

$script:IdPattern = '[0-9a-fA-F]{32}'

# ---------------------------------------------------------------- names

function ConvertTo-SafeName {
    # Turns a note or notebook title into a name Windows accepts as a file
    # or folder name.
    param([AllowNull()][AllowEmptyString()][string]$Title, [int]$MaxLength = 80)
    $name = if ($null -eq $Title) { '' } else { $Title }
    $name = $name -replace '[<>:"/\\|?*\x00-\x1F]', ' '
    $name = ($name -replace '\s+', ' ').Trim().TrimEnd('.').Trim()
    if ($name.Length -gt $MaxLength) { $name = $name.Substring(0, $MaxLength).Trim().TrimEnd('.').Trim() }
    if ($name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { $name = "_$name" }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Untitled' }
    return $name
}

function New-ExportPlan {
    # Works out where every note in the shared notebook (and its
    # sub-notebooks) goes. Returns one entry per note:
    #   Id, Title, UpdatedTime, Folder ('' or 'Sub\Sub'), BaseName
    # Notes outside the shared notebook are never included.
    param(
        [Parameter(Mandatory)][object[]]$Folders,   # id, title, parent_id
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Notes, # id, title, parent_id, updated_time
        [Parameter(Mandatory)][string]$RootId
    )
    $childrenOf = @{}
    foreach ($f in $Folders) {
        $p = [string]$f.parent_id
        if (-not $childrenOf.ContainsKey($p)) { $childrenOf[$p] = New-Object System.Collections.ArrayList }
        [void]$childrenOf[$p].Add($f)
    }

    # Folder id -> relative path
    $folderPath = @{ $RootId = '' }
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($RootId)
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        if (-not $childrenOf.ContainsKey($id)) { continue }
        $used = @{}
        foreach ($c in ($childrenOf[$id] | Sort-Object title)) {
            $n = ConvertTo-SafeName $c.title
            $n = Get-FreeName -Name $n -Used $used
            $folderPath[$c.id] = if ($folderPath[$id]) { Join-Path $folderPath[$id] $n } else { $n }
            $queue.Enqueue($c.id)
        }
    }

    $plan = New-Object System.Collections.ArrayList
    $usedByFolder = @{}
    foreach ($note in ($Notes | Where-Object { $folderPath.ContainsKey([string]$_.parent_id) } | Sort-Object title, id)) {
        $dir = $folderPath[[string]$note.parent_id]
        if (-not $usedByFolder.ContainsKey($dir)) { $usedByFolder[$dir] = @{} }
        $base = Get-FreeName -Name (ConvertTo-SafeName $note.title) -Used $usedByFolder[$dir]
        [void]$plan.Add([pscustomobject]@{
            Id          = [string]$note.id
            Title       = if ([string]::IsNullOrWhiteSpace($note.title)) { 'Untitled' } else { [string]$note.title }
            UpdatedTime = [int64]$note.updated_time
            Folder      = $dir
            BaseName    = $base
        })
    }
    return , $plan.ToArray()
}

function Get-FreeName {
    # "Notes", "Notes (2)", "Notes (3)" ... case-insensitive, like Windows.
    param([string]$Name, [hashtable]$Used)
    $candidate = $Name; $i = 2
    while ($Used.ContainsKey($candidate.ToLowerInvariant())) { $candidate = "$Name ($i)"; $i++ }
    $Used[$candidate.ToLowerInvariant()] = $true
    return $candidate
}

# ---------------------------------------------------------------- links

function Convert-JoplinLinks {
    # Joplin links look like (:/<32 hex id>). This rewrites them:
    #  - pictures and attachments -> the copied file
    #  - links to notes that are shared -> "Title" (PDF) or a relative link (HTML)
    #  - links to anything NOT shared -> plain text, so private note
    #    titles and ids never leak into the reading copy.
    param(
        [AllowEmptyString()][string]$Markdown,
        [hashtable]$NoteTargets = @{},     # id -> @{ Title; Path }  (Path relative to output root, '/' separators)
        [hashtable]$ResourcePaths = @{},   # id -> path relative to output root ('/' separators)
        [string]$FromFolder = '',          # folder of the note being written, relative to root
        [ValidateSet('pdf', 'html')][string]$Mode = 'pdf'
    )
    if ([string]::IsNullOrEmpty($Markdown)) { return '' }
    $up = Get-UpPrefix $FromFolder

    # Markdown images ![alt](:/id) and links [text](:/id), optional #anchor or "title"
    $md = [regex]::Replace($Markdown, "(!?)\[([^\]]*)\]\(:/($script:IdPattern)(#[^)\s]*)?(\s+`"[^`"]*`")?\)", {
        param($m)
        $isImage = $m.Groups[1].Value -eq '!'
        $text = $m.Groups[2].Value
        $id = $m.Groups[3].Value.ToLowerInvariant()
        if ($ResourcePaths.ContainsKey($id)) {
            $target = ConvertTo-UrlPath ($up + $ResourcePaths[$id])
            if ($isImage) { return "![$text]($target)" }
            return "[$text]($target)"
        }
        if ($NoteTargets.ContainsKey($id)) {
            $t = $NoteTargets[$id]
            if ($Mode -eq 'html') { return "[$text]($(ConvertTo-UrlPath ($up + $t.Path)))" }
            if ([string]::IsNullOrWhiteSpace($text) -or $text -eq $t.Title) { return "*(see the note `"$($t.Title)`")*" }
            return "$text *(see the note `"$($t.Title)`")*"
        }
        if ($isImage) { return '*(picture not shared)*' }
        if ([string]::IsNullOrWhiteSpace($text)) { return '*(link not shared)*' }
        return $text
    })

    # HTML inside notes: <img src=":/id"> and href=":/id"
    $md = [regex]::Replace($md, "(src|href)=([`"']):/($script:IdPattern)\2", {
        param($m)
        $attr = $m.Groups[1].Value; $q = $m.Groups[2].Value
        $id = $m.Groups[3].Value.ToLowerInvariant()
        if ($ResourcePaths.ContainsKey($id)) { return "$attr=$q$(ConvertTo-UrlPath ($up + $ResourcePaths[$id]))$q" }
        if ($Mode -eq 'html' -and $NoteTargets.ContainsKey($id)) {
            return "$attr=$q$(ConvertTo-UrlPath ($up + $NoteTargets[$id].Path))$q"
        }
        return "$attr=$q#$q"
    })

    # Any bare :/id left over (for example inside plain text)
    $md = [regex]::Replace($md, "(?<![\w/]):/($script:IdPattern)\b", '(link not shared)')
    return $md
}

function Get-UpPrefix {
    param([string]$Folder)
    if ([string]::IsNullOrEmpty($Folder)) { return '' }
    $depth = @($Folder -split '[\\/]' | Where-Object { $_ }).Count
    return ('../' * $depth)
}

function ConvertTo-UrlPath {
    # Escapes each part of a relative path for use in a link.
    param([string]$Path)
    ($Path -replace '\\', '/' -split '/' | ForEach-Object {
        if ($_ -eq '..' -or $_ -eq '.') { $_ } else { [uri]::EscapeDataString($_) }
    }) -join '/'
}

# ---------------------------------------------------------------- changes

function Compare-ReadingCopyState {
    # Compares this run's plan with what was written last time.
    # Returns New, Changed, Removed (lists of titles) and Unchanged ids.
    param(
        [object[]]$Plan,
        [hashtable]$Previous = @{}   # id -> @{ UpdatedTime; Files; Title }
    )
    $new = @(); $changed = @(); $unchanged = @(); $removed = @()
    $ids = @{}
    foreach ($p in $Plan) {
        $ids[$p.Id] = $true
        if (-not $Previous.ContainsKey($p.Id)) { $new += $p.Title; continue }
        if ([int64]$Previous[$p.Id].UpdatedTime -ne $p.UpdatedTime) { $changed += $p.Title } else { $unchanged += $p.Id }
    }
    foreach ($k in $Previous.Keys) { if (-not $ids.ContainsKey($k)) { $removed += [string]$Previous[$k].Title } }
    return [pscustomobject]@{ New = $new; Changed = $changed; Removed = $removed; Unchanged = $unchanged }
}

function Format-JoplinTime {
    param([int64]$Milliseconds)
    if ($Milliseconds -le 0) { return 'unknown' }
    return [DateTimeOffset]::FromUnixTimeMilliseconds($Milliseconds).ToLocalTime().ToString('d MMM yyyy, HH:mm', [Globalization.CultureInfo]::InvariantCulture)
}

function New-IndexMarkdown {
    # The "Start here" page: what changed since the last copy, then
    # every note with its last-updated date.
    param(
        [string]$NotebookTitle,
        [object[]]$Plan,
        [object]$Changes,
        [string]$Extension = 'pdf',
        [datetime]$Now = (Get-Date)
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# $NotebookTitle")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("This is a **reading copy**. Changes made here are not saved back. Copy made on $($Now.ToString('d MMM yyyy, HH:mm', [Globalization.CultureInfo]::InvariantCulture)).")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## What changed since the last copy')
    [void]$sb.AppendLine()
    $any = $false
    foreach ($pair in @(@('New', $Changes.New), @('Updated', $Changes.Changed), @('Removed', $Changes.Removed))) {
        foreach ($t in @($pair[1])) {
            if ($null -eq $t) { continue }
            [void]$sb.AppendLine("- **$($pair[0]):** $(ConvertTo-MarkdownText $t)"); $any = $true
        }
    }
    if (-not $any) { [void]$sb.AppendLine('Nothing changed.') }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## All notes ($(@($Plan).Count))")
    [void]$sb.AppendLine()
    $currentFolder = $null
    foreach ($p in ($Plan | Sort-Object Folder, BaseName)) {
        if ($p.Folder -ne $currentFolder) {
            $currentFolder = $p.Folder
            if ($currentFolder) {
                [void]$sb.AppendLine()
                [void]$sb.AppendLine("### $(ConvertTo-MarkdownText ($currentFolder -replace '\\', ' / '))")
                [void]$sb.AppendLine()
            }
        }
        $rel = if ($p.Folder) { Join-Path $p.Folder "$($p.BaseName).$Extension" } else { "$($p.BaseName).$Extension" }
        $label = ConvertTo-MarkdownText $p.Title
        $item = if ($Extension -eq 'html') { "[$label]($(ConvertTo-UrlPath $rel))" } else { $label }
        [void]$sb.AppendLine("- $item, updated $(Format-JoplinTime $p.UpdatedTime)")
    }
    return $sb.ToString()
}

function ConvertTo-MarkdownText {
    # Stops a title like "Week *1*" or "[draft]" from turning into formatting.
    param([string]$Text)
    return ($Text -replace '([\\`*_\[\]<>#|])', '\$1')
}

function New-NoteHtml {
    # Wraps rendered note HTML in a simple, readable page.
    param([string]$Title, [string]$BodyHtml, [int64]$UpdatedTime, [switch]$IsIndex)
    $t = [System.Net.WebUtility]::HtmlEncode($Title)
    $meta = if ($IsIndex) { '' } else { "<p class=`"meta`">Last updated $(Format-JoplinTime $UpdatedTime) &middot; reading copy</p>" }
    $heading = if ($IsIndex) { '' } else { "<h1 class=`"title`">$t</h1>" }
    return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$t</title>
<style>
  body { font-family: "Segoe UI", Arial, sans-serif; font-size: 15px; line-height: 1.55; color: #1f2328;
         max-width: 760px; margin: 0 auto; padding: 24px 20px; background: #fff; }
  h1, h2, h3 { line-height: 1.25; }
  h1.title { margin-bottom: 4px; }
  .meta { color: #59636e; font-size: 13px; margin-top: 0; }
  img { max-width: 100%; height: auto; }
  pre, code { font-family: Consolas, monospace; font-size: 13px; background: #f6f8fa; }
  pre { padding: 10px; overflow-x: auto; white-space: pre-wrap; }
  table { border-collapse: collapse; } th, td { border: 1px solid #d1d9e0; padding: 4px 8px; }
  blockquote { border-left: 3px solid #d1d9e0; margin-left: 0; padding-left: 12px; color: #59636e; }
  li.task-list-item { list-style: none; }
  a { color: #0969da; }
</style>
</head>
<body>
$heading
$meta
$BodyHtml
</body>
</html>
"@
}

# ---------------------------------------------------------------- Joplin

function Get-JoplinToken {
    # Uses -Token, then $env:JOPLIN_TOKEN, then Joplin desktop's own
    # settings file. The token is never printed.
    param([string]$Token)
    if ($Token) { return $Token }
    if ($env:JOPLIN_TOKEN) { return $env:JOPLIN_TOKEN }
    $settings = Join-Path $HOME '.config\joplin-desktop\settings.json'
    if (Test-Path $settings) {
        $s = Get-Content $settings -Raw | ConvertFrom-Json
        if ($s.PSObject.Properties['api.token'] -and $s.'api.token') { return $s.'api.token' }
    }
    throw "Couldn't find Joplin's access key. In Joplin open Tools > Options > Web Clipper, turn on the service, then try again."
}

function Invoke-JoplinApi {
    # GET one item, or every page of a list.
    param([string]$Path, [string]$Fields, [string]$Token, [int]$Port = 41184, [switch]$All, [string]$OutFile)
    $base = "http://127.0.0.1:$Port/$Path"
    $sep = if ($Path.Contains('?')) { '&' } else { '?' }
    if ($OutFile) {
        Invoke-WebRequest -Uri "$base${sep}token=$Token" -OutFile $OutFile -UseBasicParsing | Out-Null
        return
    }
    $q = if ($Fields) { "fields=$Fields&" } else { '' }
    if (-not $All) { return Invoke-RestMethod -Uri "$base$sep${q}token=$Token" }
    $items = New-Object System.Collections.ArrayList
    $page = 1
    do {
        $r = Invoke-RestMethod -Uri "$base$sep${q}limit=100&page=$page&token=$Token"
        foreach ($i in @($r.items)) { if ($null -ne $i) { [void]$items.Add($i) } }
        $page++
    } while ($r.has_more)
    return $items.ToArray()
}

function Test-JoplinRunning {
    param([int]$Port = 41184)
    try { return (Invoke-RestMethod -Uri "http://127.0.0.1:$Port/ping" -TimeoutSec 5) -eq 'JoplinClipperServer' }
    catch { return $false }
}

# ---------------------------------------------------------------- PDF

function Find-Edge {
    foreach ($p in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                     "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    throw "Microsoft Edge wasn't found. It's needed to make the PDF files (it comes with Windows 10 and 11)."
}

function ConvertTo-Pdf {
    # Prints an HTML file to PDF with Edge in the background, using its own
    # temporary profile so it never touches your normal Edge windows.
    param([string]$HtmlPath, [string]$PdfPath, [string]$EdgePath, [string]$ProfileDir)
    if (Test-Path $PdfPath) { Remove-Item $PdfPath -Force }
    $url = ([uri](Resolve-Path $HtmlPath).Path).AbsoluteUri
    $edgeArgs = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
              '--disable-extensions', '--no-pdf-header-footer', "--user-data-dir=`"$ProfileDir`"",
              "--print-to-pdf=`"$PdfPath`"", "`"$url`"")
    $p = Start-Process -FilePath $EdgePath -ArgumentList $edgeArgs -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch { } }
    for ($i = 0; $i -lt 20 -and -not (Test-Path $PdfPath); $i++) { Start-Sleep -Milliseconds 250 }
    if (-not (Test-Path $PdfPath)) { throw "Edge couldn't make the PDF for '$HtmlPath'." }
}

Export-ModuleMember -Function *
