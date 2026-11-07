BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\ReadingCopy.psm1') -Force
    $fixture = Get-Content (Join-Path $PSScriptRoot 'fixtures\sample-notebook.json') -Raw | ConvertFrom-Json
    $rootId = 'f0000000000000000000000000000001'
    $privateId = 'a0000000000000000000000000000005'
}

Describe 'ConvertTo-SafeName' {
    It 'removes characters Windows does not allow' {
        ConvertTo-SafeName 'Week 1: a/b\c?*"<>|' | Should -Be 'Week 1 a b c'
    }
    It 'gives a name to empty titles' {
        ConvertTo-SafeName '' | Should -Be 'Untitled'
        ConvertTo-SafeName $null | Should -Be 'Untitled'
        ConvertTo-SafeName '...' | Should -Be 'Untitled'
    }
    It 'avoids names Windows reserves' {
        ConvertTo-SafeName 'CON' | Should -Be '_CON'
    }
    It 'shortens very long titles' {
        (ConvertTo-SafeName ('x' * 200)).Length | Should -Be 80
    }
}

Describe 'New-ExportPlan' {
    BeforeAll { $plan = New-ExportPlan -Folders $fixture.folders -Notes $fixture.notes -RootId $rootId }

    It 'includes only notes inside the shared notebook' {
        $plan.Count | Should -Be 4
        $plan.Id | Should -Not -Contain $privateId
    }
    It 'keeps sub-notebooks as folders' {
        ($plan | Where-Object Title -eq 'Chicken soup?').Folder | Should -Be (Join-Path 'Recipes Mum Gran' 'Soups')
        ($plan | Where-Object Title -eq 'Adobo').Folder | Should -Be 'Recipes Mum Gran'
    }
    It 'gives two notes with the same title different file names' {
        $names = ($plan | Where-Object Title -eq 'Welcome').BaseName | Sort-Object
        $names | Should -Be @('Welcome', 'Welcome (2)')
    }
    It 'returns nothing for an empty notebook' {
        $empty = New-ExportPlan -Folders $fixture.folders -Notes @() -RootId $rootId
        @($empty).Count | Should -Be 0
    }
}

Describe 'Convert-JoplinLinks' {
    BeforeAll {
        $pic = 'b0000000000000000000000000000001'
        $targets = @{ 'a0000000000000000000000000000004' = @{ Title = 'Adobo'; Path = 'Recipes Mum Gran\Adobo.pdf' } }
        $res = @{ $pic = '_attachments/b0000000 photo.png' }
    }
    It 'points pictures at the copied file' {
        $md = Convert-JoplinLinks -Markdown "![photo](:/$pic)" -ResourcePaths $res
        $md | Should -Be '![photo](_attachments/b0000000%20photo.png)'
    }
    It 'adds ../ for notes inside sub-notebooks' {
        $md = Convert-JoplinLinks -Markdown "![photo](:/$pic)" -ResourcePaths $res -FromFolder 'Recipes Mum Gran\Soups'
        $md | Should -Be '![photo](../../_attachments/b0000000%20photo.png)'
    }
    It 'turns a link to a shared note into its title in PDF mode' {
        $md = Convert-JoplinLinks -Markdown '[how to](:/a0000000000000000000000000000004)' -NoteTargets $targets
        $md | Should -Be 'how to *(see the note "Adobo")*'
    }
    It 'keeps a real link to a shared note in web page mode' {
        $md = Convert-JoplinLinks -Markdown '[how to](:/a0000000000000000000000000000004)' -NoteTargets $targets -Mode html
        $md | Should -Be '[how to](Recipes%20Mum%20Gran/Adobo.pdf)'
    }
    It 'never shows the id of a private note' {
        $md = Convert-JoplinLinks -Markdown "see [my secret](:/$privateId) and ![x](:/$privateId) and :/$privateId" -NoteTargets $targets
        $md | Should -Not -Match $privateId
        $md | Should -Match 'my secret'
        $md | Should -Match 'picture not shared'
    }
    It 'handles pictures written as HTML' {
        $md = Convert-JoplinLinks -Markdown "<img src=`":/$pic`" width=`"200`">" -ResourcePaths $res
        $md | Should -Be '<img src="_attachments/b0000000%20photo.png" width="200">'
        Convert-JoplinLinks -Markdown "<img src=`":/$privateId`">" | Should -Be '<img src="#">'
    }
    It 'leaves normal web links alone' {
        Convert-JoplinLinks -Markdown '[site](https://joplinapp.org/)' | Should -Be '[site](https://joplinapp.org/)'
    }
}

Describe 'Compare-ReadingCopyState' {
    It 'finds new, changed and removed notes' {
        $plan = New-ExportPlan -Folders $fixture.folders -Notes $fixture.notes -RootId $rootId
        $previous = @{
            'a0000000000000000000000000000001' = @{ UpdatedTime = 1762300000000; Title = 'Welcome' }
            'a0000000000000000000000000000004' = @{ UpdatedTime = 1700000000000; Title = 'Adobo' }
            'a0000000000000000000000000000099' = @{ UpdatedTime = 1700000000000; Title = 'Old note' }
        }
        $c = Compare-ReadingCopyState -Plan $plan -Previous $previous
        $c.New | Sort-Object | Should -Be @('Chicken soup?', 'Welcome')
        $c.Changed | Should -Be @('Adobo')
        $c.Removed | Should -Be @('Old note')
        $c.Unchanged | Should -Be @('a0000000000000000000000000000001')
    }
}

Describe 'New-IndexMarkdown' {
    BeforeAll {
        $plan = New-ExportPlan -Folders $fixture.folders -Notes $fixture.notes -RootId $rootId
        $changes = [pscustomobject]@{ New = @('Chicken soup?'); Changed = @(); Removed = @('Old *note*') }
    }
    It 'lists what changed and every note' {
        $md = New-IndexMarkdown -NotebookTitle 'Family' -Plan $plan -Changes $changes
        $md | Should -Match '\*\*New:\*\* Chicken soup\?'
        $md | Should -Match 'Old \\\*note\\\*'
        $md | Should -Match 'All notes \(4\)'
        $md | Should -Not -Match 'My diary'
    }
    It 'says so when nothing changed' {
        $none = [pscustomobject]@{ New = @(); Changed = @(); Removed = @() }
        New-IndexMarkdown -NotebookTitle 'Family' -Plan $plan -Changes $none | Should -Match 'Nothing changed'
    }
    It 'makes clickable links in web page mode' {
        $md = New-IndexMarkdown -NotebookTitle 'Family' -Plan $plan -Changes $changes -Extension html
        $md | Should -Match '\[Adobo\]\(Recipes%20Mum%20Gran/Adobo\.html\)'
    }
}

Describe 'New-NoteHtml' {
    It 'escapes the title so it cannot break the page' {
        $html = New-NoteHtml -Title '<b>Hi</b> & bye' -BodyHtml '<p>x</p>' -UpdatedTime 1762300000000
        $html | Should -Match '&lt;b&gt;Hi&lt;/b&gt; &amp; bye'
        $html | Should -Match 'reading copy'
    }
}

Describe 'Daily task scripts' {
    It '<_> has no syntax errors and needs -Output' -ForEach @('run-daily.ps1', 'register-daily-task.ps1') {
        $path = Join-Path $PSScriptRoot "..\schedule\$_"
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
        $output = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Output' }
        $output | Should -Not -BeNullOrEmpty
        $output.Attributes.NamedArguments.ArgumentName | Should -Contain 'Mandatory'
    }
}
