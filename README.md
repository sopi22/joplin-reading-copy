# Reading Copy for Joplin

**Share one Joplin notebook with your family as PDFs they can read but not change.**

My dad writes a lot of notes in [Joplin](https://joplinapp.org). My brother,
my mom and I want to read them, but we don't need to edit them, and his other
notes are private. Joplin's free sync shares everything or nothing, and
importing a `.jex` export again makes duplicate copies instead of updating
the old ones.

So this tool takes **one notebook** (for example `Family`) and turns every note
in it into a PDF in a folder you choose. We use a shared Proton Drive folder,
so the copy is end-to-end encrypted and the rest of the family can only view it.

- Only the notebook you name (and its sub-notebooks) is copied. Nothing else.
- Each run updates the copy: changed notes get a new PDF, deleted notes are
  removed, unchanged notes are left alone.
- A `00 Start here` page lists every note and **what changed since last time**.
- Links to notes that aren't shared become plain text, so private note titles
  never show up in the copy.
- Pictures, checklists and tables are kept.
- It only talks to Joplin on your own computer. Nothing is sent anywhere by
  this tool. Uploading is done by whatever sync app owns the folder.

## What you need

- Windows 10 or 11
- [Joplin](https://joplinapp.org) desktop app
- PowerShell 7 (free): `winget install Microsoft.PowerShell`
- Microsoft Edge (already on Windows). It is used in the background to make the PDFs.

## Set it up

1. **Download** this repo (green *Code* button > *Download ZIP*) and unzip it,
   for example to `D:\Tools\joplin-reading-copy`.
2. **Unblock it.** Windows blocks scripts downloaded from the internet. Open
   PowerShell 7 (`pwsh`) and run:
   ```powershell
   Get-ChildItem -Recurse D:\Tools\joplin-reading-copy | Unblock-File
   ```
3. **Turn on Joplin's local connection:** in Joplin open *Tools > Options >
   Web Clipper* and click *Enable Web Clipper Service*. The tool finds the
   access key by itself. Joplin has to be open when the tool runs.
4. **Make the notebook** you want to share, for example `Family`, and put the
   notes in it.
5. **Pick the output folder.** For Proton Drive, that's a folder inside your
   Proton Drive folder, shared with your family as *Viewer*.

## Run it

```powershell
cd D:\Tools\joplin-reading-copy
.\joplin-reading-copy.ps1 -Output "D:\ProtonDrive\My files\Family notes"
```

You'll see something like:

```
Reading copy of 'Family' -> D:\ProtonDrive\My files\Family notes
  12 notes: 1 new, 2 updated, 0 removed since last time
  3 files made, 9 unchanged (left as they were), 0 old files removed
  5 pictures, 1 attachments
  All done.
```

Options:

| Option | What it does |
|---|---|
| `-Notebook "Name"` | Notebook to share. Default: `Family` |
| `-Output "folder"` | Where the copy goes (required) |
| `-Format html` | Web pages with pictures instead of PDFs |
| `-Force` | Remake every file, even unchanged ones |

Files that aren't pictures (for example a Word file attached to a note) are
copied to an `_attachments` folder.

## Run it every day by itself (optional)

In *Task Scheduler* > *Create Basic Task*: pick a time, choose *Start a
program*, program `pwsh.exe`, arguments:

```
-NoProfile -File "D:\Tools\joplin-reading-copy\joplin-reading-copy.ps1" -Output "D:\ProtonDrive\My files\Family notes"
```

Joplin has to be open at that time, or the run just says so and stops.

## What it never does

- It never changes or deletes anything in Joplin. It only reads.
- It never reads notes outside the notebook you name (it only asks Joplin for
  their titles and dates to know which notebook they're in).
- It only deletes files in the output folder that **it made itself** on an
  earlier run. Anything else you put there is left alone.
- It never prints note text or Joplin's access key.

## Limits

- Links between notes become "(see the note ...)" in PDFs, since PDF files
  in a shared drive can't open each other. Use `-Format html` if you want
  clickable links.
- If a note is renamed, other notes that link to it show the new name only
  after they change too, or after a run with `-Force`.
- Joplin's math and diagram blocks (KaTeX, Mermaid) are shown as plain text.

## How I tested it

- 20 automatic tests with made-up notes in `tests/fixtures` (run with
  [Pester](https://pester.dev) 5+, also on GitHub Actions on Windows):
  ```powershell
  Invoke-Pester .\tests
  ```
- By hand on a real Joplin with a test notebook: pictures, checklists,
  tables, a sub-notebook, a link to a shared note, a link to a note that
  wasn't shared, then editing one note and deleting another. The PDFs were
  checked page by page.

## Related projects

- [Sync to Git Remote](https://github.com/RomPiot/joplin-sync-to-git-remote)
  exports **all** notes to a git repo as a backup. This tool is for sharing
  one notebook with people, read-only.
- People keep asking for scheduled exports of one notebook on the Joplin
  forum ([1](https://discourse.joplinapp.org/t/automating-exports-of-notebooks-to-html/14894),
  [2](https://discourse.joplinapp.org/t/is-there-a-possibility-to-schedule-export-all/32014),
  [3](https://discourse.joplinapp.org/t/how-can-i-export-certain-ntoebooks-to-a-certain-system-folder-on-using-the-cli/25362)).
  This is my answer to that for my family.

Built with Joplin's [Data API](https://joplinapp.org/help/api/references/rest_api/),
PowerShell 7's `ConvertFrom-Markdown` and Edge's headless PDF printing.

Not made by or connected to the Joplin team. Joplin is a trademark of its owner.

## License

MIT, see [LICENSE](LICENSE). Made by Jhoana Sophia C. Munar.
