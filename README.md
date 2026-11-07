# Reading Copy for Joplin

**Share one Joplin notebook with your family as PDFs they can read but not change,
for example through a shared Proton Drive folder.**

My dad keeps his notes in [Joplin](https://joplinapp.org). My brother and I want to
read some of them, but we don't need to edit them, and most of his notes are
private. Joplin's free sync shares a whole profile or nothing, and importing a
`.jex` export a second time makes duplicate copies instead of updating the old
ones. So I wrote a small tool that copies **one notebook** to a folder as PDFs
and keeps that copy up to date.

## Features

- Copies only the notebook you name (and its sub-notebooks). Nothing else.
- One PDF per note, with pictures, checklists and tables, plus a
  `00 Start here.pdf` that lists every note and **what changed since last time**.
- Each run updates the copy: changed notes get a new PDF, deleted notes are
  removed, unchanged files are left alone (so a sync app doesn't upload
  everything again).
- Links to notes that aren't shared become plain text, so private note titles
  never show up in the copy.
- Works with any synced folder: Proton Drive, OneDrive, Google Drive, Syncthing,
  a USB stick. This README uses Proton Drive because it's end-to-end encrypted
  and lets you share a folder as *Viewer* (read-only) for free.
- Never changes anything in Joplin. It only reads.

## Tech stack

- PowerShell 7 (Windows)
- Joplin's local [Data API](https://joplinapp.org/help/api/references/rest_api/)
  (the "Web Clipper service", only reachable from your own computer)
- PowerShell 7's built-in `ConvertFrom-Markdown` to turn notes into HTML
- Microsoft Edge in headless mode to print the HTML to PDF
- [Pester](https://pester.dev) 5+ for tests, run on Windows by GitHub Actions
- No Docker: it needs the Joplin desktop app on your own Windows PC, so a
  container wouldn't help.

## Step-by-step guide

The person who writes the notes (for us, Dad) does part A once and part B
whenever the notes change. The readers only do part C.

### A. One-time setup (on the computer with Joplin)

**1. Make the notebook to share in Joplin**

1. Open Joplin. In the left sidebar, right-click **Notebooks** → **New notebook**.
2. Name it `Family` (any name works, see `-Notebook` below).
3. Put notes in it: write new ones there, or drag existing notes onto it
   (or right-click a note → **Move to notebook** → `Family`).
   Sub-notebooks are fine; they become folders in the copy.

**2. Turn on Joplin's local connection**

In Joplin: **Tools** → **Options** → **Web Clipper** → **Enable Web Clipper Service**.
The tool finds the access key by itself. Joplin has to be open when the tool runs.

**3. Install PowerShell 7** (free, from Microsoft). In a normal PowerShell window:

```powershell
winget install Microsoft.PowerShell
```

**4. Get the tool**

With git:

```powershell
git clone https://github.com/sopi22/joplin-reading-copy.git D:\Tools\joplin-reading-copy
```

Or without git: on GitHub click **Code** → **Download ZIP** and unzip it to
`D:\Tools\joplin-reading-copy`. Then open PowerShell 7 (Start → type `pwsh`)
and unblock the files, because Windows blocks scripts downloaded from the internet:

```powershell
Get-ChildItem -Recurse D:\Tools\joplin-reading-copy | Unblock-File
```

**5. Set up Proton Drive**

1. Make a free Proton account at <https://proton.me/drive> if you don't have one
   (the free plan has 5 GB).
2. Install the **Proton Drive** app for Windows and sign in.
3. Optional, to keep the files off C:: in the app open **Settings** → **Location**
   → **Change** and pick an **empty** folder on another drive, for example
   `D:\ProtonDrive`. Do this before syncing anything.
4. In File Explorer, open your Proton Drive folder → **My files** and create a
   new folder, for example `Family notes`. The app uploads it.

**6. Share the folder as read-only**

1. Go to <https://drive.proton.me> and sign in.
2. Right-click **Family notes** → **Share**.
3. Type each reader's email address, set the permission to **Viewer**, and click **Share**.

### B. Make or update the copy

Open PowerShell 7 (Start → type `pwsh`), make sure Joplin is open, and run:

```powershell
cd D:\Tools\joplin-reading-copy
.\joplin-reading-copy.ps1 -Output "D:\ProtonDrive\My files\Family notes"
```

Change the `-Output` path to your own Proton Drive folder. Real output from our
first run:

```
Reading copy of 'Family' -> D:\ProtonDrive\My files\Family notes
  47 notes: 47 new, 0 updated, 2 removed since last time
  47 files made, 0 unchanged (left as they were), 2 old files removed
  0 pictures, 0 attachments
  All done.
```

and from a run where nothing had changed:

```
Reading copy of 'Family' -> D:\ProtonDrive\My files\Family notes
  47 notes: 0 new, 0 updated, 0 removed since last time
  0 files made, 47 unchanged (left as they were), 0 old files removed
  0 pictures, 0 attachments
  All done.
```

The Proton Drive app uploads the new PDFs within a few minutes. Run it again
whenever you add or change notes, or let Windows do it every day (below).

| Option | What it does |
|---|---|
| `-Notebook "Name"` | Notebook to share. Default: `Family` |
| `-Output "folder"` | Where the copy goes (required) |
| `-Format html` | Web pages with pictures and clickable links instead of PDFs |
| `-Force` | Remake every file, even unchanged ones |

Files attached to notes that aren't pictures (for example a Word file) are
copied to an `_attachments` folder.

### C. Read the notes (for the family)

1. Go to <https://drive.proton.me> (or open the **Proton Drive** phone app).
2. Sign in with **your own** Proton account, the address the folder was shared with.
3. Click **Shared with me** (phone app: the **Shared** tab).
4. Open **Family notes**, then **`00 Start here.pdf`**. It shows every note and what changed.

You can read and download the PDFs, but not change them. If Proton sent an
invitation email, open its link once first.

### D. Optional: update the copy every day by itself

In **Task Scheduler** → **Create Basic Task**: give it a name, pick **Daily** and
a time, choose **Start a program**, program `pwsh.exe`, and as arguments:

```
-NoProfile -File "D:\Tools\joplin-reading-copy\joplin-reading-copy.ps1" -Output "D:\ProtonDrive\My files\Family notes"
```

Joplin has to be open at that time. If it isn't, the run just says so and stops.

## What it never does

- It never changes or deletes anything in Joplin.
- It never reads the text of notes outside the notebook you name. It only asks
  Joplin for their titles and dates, to know which notebook they're in.
- It only deletes files in the output folder that **it made itself** on an
  earlier run. Anything else in that folder is left alone.
- It never prints note text or Joplin's access key. It keeps a small record
  of what it made in `%LOCALAPPDATA%\joplin-reading-copy`.

## Limits

- In PDFs, links between notes become "(see the note ...)", because PDFs in a
  shared drive can't open each other. Use `-Format html` for clickable links.
- If a note is renamed, other notes that link to it show the new name only
  after they change too, or after a run with `-Force`.
- Joplin's math and diagram blocks (KaTeX, Mermaid) are shown as plain text.
- Windows only (it uses Edge to make the PDFs).

## How I tested it

- 20 automatic tests with made-up notes (`tests/fixtures`), run on every push
  by GitHub Actions on Windows. To run them yourself in PowerShell 7:
  ```powershell
  Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5 -SkipPublisherCheck -Force
  Invoke-Pester .\tests
  ```
- By hand on a real Joplin with a test notebook: pictures, checklists, tables, a
  sub-notebook, a link to a shared note, a link to a note that wasn't shared,
  then editing one note and deleting another. I checked the PDFs page by page.
- In use for our family: 47 notes in 5 folders, shared through Proton Drive.

## Inspiration and related projects

This is written from scratch, not forked.

- People on the Joplin forum keep asking how to export one notebook on a schedule
  ([1](https://discourse.joplinapp.org/t/automating-exports-of-notebooks-to-html/14894),
  [2](https://discourse.joplinapp.org/t/is-there-a-possibility-to-schedule-export-all/32014),
  [3](https://discourse.joplinapp.org/t/how-can-i-export-certain-ntoebooks-to-a-certain-system-folder-on-using-the-cli/25362)).
  The answers there are scripts around the Joplin terminal app. This tool is my
  version of that for sharing with family.
- [Sync to Git Remote](https://github.com/RomPiot/joplin-sync-to-git-remote)
  is a Joplin plugin that exports **all** notes to a git repo as a backup.
  This tool does something different: one notebook, as PDFs, for people to read.

Not made by or connected to the Joplin team. Joplin is a trademark of its owner.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Jhoana Sophia Munar.
