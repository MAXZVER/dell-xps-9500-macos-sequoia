# Trackpad gestures and Safari

Comfort rather than function — nothing here is needed to make the machine work. It is in this repository
because the first part turned out to say something useful about the trackpad on a hackintosh, and because
both answers took longer to find than they should have.

## Four-finger tap as a middle click

macOS has no middle mouse button, so browsers lose two things Linux and Windows users take for granted:
middle-click a link to open it in a background tab, and middle-click a tab to close it. Safari supports both
— there is simply no way to produce the click.

There is also **no built-in gesture for either action**, and no Safari setting or extension can add one:
Safari extensions have no access to the browser's own interface.

What does work is emulating the middle button, and one gesture then covers both actions, each in the right
context.

### Why the trackpad can do this at all

Worth stating, because on a hackintosh it is not obvious. The 9500's I²C trackpad goes through
`VoodooI2C` 2.9.1 → `VoodooI2CHID` → `VoodooInput` 1.1.7, and VoodooInput presents it to Apple's own
`AppleMultitouchDriver` as a **Magic Trackpad 2**:

```bash
ioreg -rc AppleMultitouchDevice -w0 | grep -E '"Product"|"MT Built-In"'
```

```
"Product" = "Magic Trackpad 2"
"MT Built-In" = Yes
```

That is the whole reason third-party gesture tools work here: they read fingers through the private
multitouch framework, and as far as that framework is concerned this is a real Apple trackpad.

The finger count is not a limit either:

```bash
ioreg -l -w0 -r -c VoodooI2CMultitouchHIDEventDriver | grep -o '"Transducer Count"=[0-9]*'
```

```
"Transducer Count"=5
```

Five simultaneous contacts, and `TrackpadFourFingerGestures = Yes`.

### Why four fingers and not three

Three fingers is the usual choice, and it is the wrong one on this machine, for two concrete reasons:

```bash
defaults read com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag        # 1
defaults read com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture  # 2 = Look up
```

- **Three-finger drag is on**, and it is genuinely useful — it is how you select text and move windows
  without pressing down. A three-finger tap tool competes with it and misfires.
- **Three-finger tap is already assigned** to Look up / data detectors (`2`).

Four fingers is free. macOS binds four-finger *swipes* and the four-finger *pinch*, but there is **no
four-finger tap setting at all** — the key does not exist:

```bash
for k in TrackpadFourFingerHorizSwipeGesture TrackpadFourFingerVertSwipeGesture \
         TrackpadFourFingerPinchGesture TrackpadFiveFingerPinchGesture; do
  echo "$k = $(defaults read com.apple.AppleMultitouchTrackpad $k)"
done
```

All four return `2`; nothing reads a four-finger tap. So the gesture can be taken over without giving
anything up, and the three-finger gestures stay exactly as they were.

### Setting it up

[MiddleClick](https://github.com/artginzburg/MiddleClick) (GPL-3.0) is the one to use, because the finger
count is configurable. Version 3.3.0 was used here.

```bash
brew install --cask middleclick        # or download the .zip from GitHub releases
defaults write art.ginzburg.MiddleClick fingers -int 4
```

`fingers` accepts 2, 4, 5 as well as the default 3.

Then grant it **Accessibility** in System Settings → Privacy & Security, and enable *Start at login* from its
menu bar item — without that the gesture is gone after a reboot.

Verify the permission actually landed, rather than trusting the checkbox:

```bash
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "select client,auth_value from access where service='kTCCServiceAccessibility'"
```

`2` means allowed, `0` means the entry exists but is denied — which is what you see if the prompt appeared
and was dismissed.

Be aware of what you are granting: Accessibility lets the app observe every input event. The source is
public and the release is notarized (`Developer ID Application: Arthur Ginzburg (R2294BC6J8)`), which is
checkable before installing:

```bash
spctl -a -vvv /Applications/MiddleClick.app
```

```
accepted
source=Notarized Developer ID
```

Do **not** strip the quarantine attribute to make it launch. A notarized app does not need it, and removing
it defeats the check that told you the app is what it claims to be.

### Result

Four-finger tap on a link opens it in a background tab; four-finger tap on a tab closes it. Works in Safari,
Chrome and Firefox alike, since it is a real middle click and not a browser-specific hack.

If taps misfire, the tool has two thresholds:

| Key | Default | Meaning |
|---|---|---|
| `maxDistanceDelta` | 0.05 | how far the cursor may move between touch and release |
| `maxTimeDelta` | 300 | maximum tap duration, ms |

On an emulated trackpad a slightly longer `maxTimeDelta` can help.

## Safari: restore the last session on quit

Safari's default is to open a new empty window, discarding what was open when you quit. The setting that
changes this is *Safari opens with: All windows from last session*, in Settings → General, or:

```bash
defaults write com.apple.Safari AlwaysRestoreSessionAtLaunch -bool true
```

Check the system-wide flag too — it gates window restoration for every application:

```bash
defaults read -g NSQuitAlwaysKeepsWindows
```

`1` means windows are restored (the System Settings → Desktop & Dock checkbox *Close windows when quitting an
application* is **un**checked). It was already `1` on this machine, so only the Safari-side setting was
missing.

Related and often more useful day to day:

| | |
|---|---|
| Reopen the last closed tab | **⇧⌘T** |
| List of recently closed | History → Recently Closed |
| Restore the previous session by hand | History → Reopen All Windows from Last Session |

Private windows are never restored. That is by design, not a broken setting.

## Safari: tabs in a sidebar — only half possible

Asked and answered honestly: **Safari has a vertical tab list, but the horizontal tab bar cannot be hidden.**
Safari 18.6 was tested.

`⌃⌘S` (View → Show Sidebar) opens a sidebar that lists the current window's tabs and Tab Groups vertically —
draggable, closable, with favicons. But it is the same panel that holds Bookmarks and Reading List: a panel,
not a replacement for the tab bar. `View → Hide Tab Bar` is only available with a single tab open, so with
several tabs you get both the sidebar and the horizontal strip.

To open it in every new window:

```bash
defaults write com.apple.Safari ShowSidebarInNewWindows -bool true
```

Two things learned trying this:

- **Turn on compact tabs as well** (Settings → Tabs → Compact) or the duplication is annoying — the top strip
  shrinks to something close to icons.
- **Set the sidebar's visibility in Safari's own interface, not with `defaults`.** Safari records the panel's
  state itself when it quits, so a window left with the sidebar open will write that back and override an
  external change. `AlwaysRestoreSessionAtLaunch` above does land in the plist immediately and is safe to set
  from the command line; the sidebar state is not.

If you want true vertical tabs *instead of* horizontal ones, Safari cannot do it at any setting. That needs a
different browser — [Orion](https://browser.kagi.com/) is the closest fit for a Safari user, being WebKit,
native, and able to run Safari extensions.
