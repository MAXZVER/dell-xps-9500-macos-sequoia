# Yandex.Disk sync that does not run all day

> 🇷🇺 [Русская версия](ru/yandex-sync.md)

Nothing here is specific to the XPS 9500 — it works on any Mac. It lives in this repository because
it was built on this machine, and because the interesting part is a design constraint that applies to
every laptop: **a sync client has no business burning battery while you are not using it.**

The official Yandex.Disk client for macOS keeps a daemon resident and polls. This does the same job with
two Python files and one Swift file, and spends its idle time asleep.

| | |
|---|---|
| [`tools/yandex-sync/yasync.py`](../tools/yandex-sync/yasync.py) | The engine: config, sync, conflict detection, three-way ancestor snapshots |
| [`tools/yandex-sync/yadiff.py`](../tools/yandex-sync/yadiff.py) | Three-pane merge UI in the browser, JetBrains-style |
| [`tools/yandex-sync/YandexSync.swift`](../tools/yandex-sync/YandexSync.swift) | Menu-bar app: folder picker, status, and the decision of *when* to sync |

Dependencies: `rclone` (one static binary) and macOS itself. The Python side is standard library only —
no `pip`, no virtualenv. The Swift side is one file, compiled with the Command Line Tools.

---

## Install

```bash
# rclone, if you do not have it
mkdir -p ~/bin && curl -fsSL https://downloads.rclone.org/rclone-current-osx-amd64.zip -o /tmp/rc.zip
unzip -jo /tmp/rc.zip '*/rclone' -d ~/bin && chmod +x ~/bin/rclone

# authorise the remote — this opens a browser, and the token stays in ~/.config/rclone/rclone.conf
~/bin/rclone config create yandex yandex

cp tools/yandex-sync/yasync.py tools/yandex-sync/yadiff.py ~/bin/
chmod +x ~/bin/yasync.py
~/bin/yasync.py init

swiftc -O tools/yandex-sync/YandexSync.swift -o ~/bin/YandexSync
~/bin/YandexSync &
```

Then pick folders from the menu-bar icon, and turn on **Запускать при входе** ("start at login") if you
want it there permanently.

The OAuth token lives in rclone's own config file and is never read, copied or logged by any of this.

---

## When it syncs, and why that list is short

There is no timer and no polling loop anywhere. The app sits idle until the kernel wakes it, and there
are exactly four things that do:

| Trigger | Mechanism | Why |
|---|---|---|
| A file changed locally | `FSEventStream` on `~/YandexDisk`, 2 s kernel coalescing + 10 s debounce | Push from the kernel. A burst of saves costs exactly one sync |
| Finder became active | `NSWorkspace.didActivateApplicationNotification`, throttled to once per 2 min | The closest thing macOS has to "the user opened a folder" |
| Woke from sleep | `NSWorkspace.didWakeNotification` | The remote has probably moved on while the lid was shut |
| Network came back | `NWPathMonitor`, only after it had been down | Retry the sync that failed offline, once, at the moment it can succeed |

**There is no "folder was opened" event in macOS.** No public API reports it; Finder does not broadcast it.
Anyone claiming otherwise is describing either a polling loop or an AppleScript that asks Finder for its
front window. Finder activation is the honest approximation, which is why it is on a leash.

Idle cost is what an idle `NSStatusItem` costs: no timers, no wakeups, no CPU.

---

## Sync itself: `rclone bisync`

Two-way sync is a solved problem and this is not the place to re-solve it badly. `rclone bisync` finds
changes on both sides, including deletions and conflicts, and keeps its own state in a workdir.

The flags that matter:

```
--conflict-resolve none        # never pick a winner behind the user's back
--conflict-loser pathname      # keep BOTH versions, renamed
--conflict-suffix local,remote # → doc.txt.local and doc.txt.remote
--resilient --recover          # survive small interruptions without demanding a full resync
```

`--conflict-resolve none` plus `--conflict-loser pathname` is the whole basis of the merge feature: when
both sides changed, rclone leaves `doc.txt.local` and `doc.txt.remote` side by side and that is the input
to the diff.

### The safety abort is never bypassed silently

`bisync` refuses to proceed when a suspiciously large share of files changed at once — that pattern
usually means a folder was moved or emptied by accident, not edited. `yasync.py` detects the abort,
records `lastResult: needs-confirm` with the reason, and stops. The menu offers **Подтвердить массовое
изменение…**, which shows what `bisync` actually said before adding `--force`.

Automatically passing `--force` would make the tool convenient and occasionally catastrophic.

---

## Conflicts: a real three-way merge

Open a conflict from the menu and a local HTTP server on `127.0.0.1` (random port) serves a merge page:
**left is Yandex.Disk, right is this Mac, the middle pane is the live result.** Chevrons in the gutters
add a side to the result. Clicking left then right puts left above right; clicking right then left
reverses it — the order of clicks is the order of lines, so no separate "both" buttons are needed.

Word-level highlighting inside changed lines, a change ruler on the right edge, undo/redo over every
step, <kbd>F7</kbd> to walk the differences, and a manual edit overlay for the result.

### Why two versions are not enough, and where the third comes from

A line present on the left and absent on the right is either *"the left side added it"* or *"the right
side deleted it"*. These are different facts and **a diff between two versions cannot tell them apart.**
Nor can file timestamps: a file has one `mtime` for the whole file, so it can tell you which version was
saved later, but never which *line* changed later. Per-line history does not exist anywhere on disk.

The only thing that separates those cases is a third version — the common ancestor.

So `yasync.py` keeps one. After every successful sync, when both sides agree by definition, it snapshots
the folder's contents into `~/Library/Application Support/YandexSync/base/` — gzipped, incremental
(a file is re-copied only if its size or mtime changed), skipping anything over 32 MB. Files currently in
conflict are deliberately *not* re-snapshotted: their old ancestor is exactly what the merge needs.

With an ancestor, `build_blocks3` classifies every hunk:

| Both sides vs ancestor | Verdict |
|---|---|
| Only the left changed | Apply the left. Unambiguous |
| Only the right changed | Apply the right. Unambiguous — **including deletions**, which a two-way diff would have mistaken for an addition on the other side |
| Both changed, identically | Not a difference at all; not shown |
| Both changed, differently | A genuine conflict. Left for the human |

Unambiguous blocks are pre-applied when the page opens, and **Слить неконфликтующие** re-applies them
after you have undone things. Genuine conflicts are never auto-merged.

Without an ancestor — a file that appeared already in conflict, or one over the size limit — the page
says so, and auto-merge falls back to the only case that stays unambiguous with two versions: a one-sided
insertion. The status bar labels that count as approximate rather than pretending otherwise.

### Office documents

`.docx`, `.doc`, `.rtf`, `.odt` are converted with `textutil`, which ships with macOS. `.xlsx` and `.pptx`
are unzipped and their XML read with the standard library — spreadsheets come out as `Sheet!A1: value`
lines, presentations as slide text. So you can *see* what differs inside an Office document.

You cannot rebuild a `.docx` from text, so for those files the merge is per-file, not per-block: pick a
side. The page says so instead of offering buttons that would produce a corrupt document.

`.xls` and `.ppt` (the old binary formats) are not read at all.

---

## Files and state

| Path | What |
|---|---|
| `~/YandexDisk/` | The synced folders themselves |
| `~/Library/Application Support/YandexSync/config.json` | Which folders, when each last synced |
| `~/Library/Application Support/YandexSync/bisync/` | `rclone bisync` state |
| `~/Library/Application Support/YandexSync/base/` | Gzipped ancestor snapshots |
| `~/Library/Logs/yandex-sync.log` | Log |
| `~/.config/rclone/rclone.conf` | The OAuth token — rclone's, not ours |

The engine is usable on its own:

```bash
yasync.py ls                  # folders on the Disk
yasync.py add Документы       # take one under sync (first run does a resync)
yasync.py sync --all
yasync.py status              # or: state, for JSON
yasync.py conflicts
yasync.py resolve doc.txt     # opens the merge page
```

---

## Honest limits

- **The ancestor only starts existing after the first successful sync.** A conflict that predates the
  snapshot gets the two-way fallback.
- **Files over 32 MB have no ancestor** and never will — line-merging them is not a real workflow.
- **An edit made during a sync can be missed by the file watcher.** The watcher ignores events while
  syncing and for 5 s after, because otherwise the tool's own writes retrigger it forever. Such an edit
  is picked up at the next trigger, not instantly.
- **Finder activation is a proxy**, not a real "folder opened" signal — see above.
- **Case sensitivity and extended attributes** are `rclone`'s business, not ours; Finder tags and
  resource forks do not survive a round trip.
