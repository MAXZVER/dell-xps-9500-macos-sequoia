# Audio, keyboard, card reader

Smaller fixes that each cost more time than they should have.

## Audio

```
PciRoot(0x0)/Pci(0x1F,0x3)
    layout-id   = 13
    hda-gfx     = onboard-1
    model       = Smart Sound Technology Audio Controller
```

with `AppleALC.kext`. Speakers, headphone jack and HDMI audio all work out of the box.

Note that `#device-id = C8 9D 00 00` is present but **commented out** (the leading `#` disables the
property). The controller is recognised without spoofing it to `0x9DC8`; the entry is left in place as a
fallback if a future macOS stops matching.

### The microphone problem

The internal microphone works, but by default you get silence from every application. The cause is
specific and worth stating plainly:

AppleALC with `layout-id 13` creates **two** input engines — the internal microphone and the 3.5 mm jack
input. The jack engine appears about 15 seconds after boot, *later* than the internal one, and `coreaudiod`
follows a rule of "the most recently appeared device becomes the default". So the default input becomes a
jack with nothing plugged into it. Your saved preference is correct — it just gets overridden.

`tools/micguard.swift` watches for this and puts the default input back on the internal microphone. It
deliberately leaves USB and Bluetooth microphones alone, and only intervenes when the default has become a
*built-in* device that is not the internal mic.

```bash
swiftc -O tools/micguard.swift -o ~/tools/micguard
cp scripts/com.local.micguard.plist ~/Library/LaunchAgents/   # edit YOUR_USERNAME first
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.local.micguard.plist
```

(The source comments are in Russian — it was written while solving this on a Russian-language system.)

## Keyboard and trackpad

`VoodooPS2Controller.kext` with its `VoodooPS2Keyboard` plug-in for the keyboard, `VoodooI2C` +
`VoodooI2CHID` for the precision trackpad. Gestures work.

### Putting Command where a Mac user expects it

On a PC keyboard the physical key next to the spacebar is `Alt`, which macOS reads as `Option`. If you want
Mac-style `Cmd` in that position, swap the modifiers:

`scripts/com.local.keyswap.plist` installs a LaunchDaemon that runs `hidutil` at boot and swaps Option ↔
Command on both sides.

```bash
sudo cp scripts/com.local.keyswap.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.keyswap.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.keyswap.plist
```

**It has to be a daemon.** `hidutil property --set` does not persist — the mapping is gone after every
reboot, and macOS's own Modifier Keys panel does not cover this remap. Setting it once by hand looks like it
worked and then quietly reverts.

### Russian layout: use "Russian – PC"

macOS's plain **Russian** layout puts `.` and `,` in different places than a PC keyboard, and `ё` somewhere
else entirely. If the machine's keycaps are a PC layout, this is maddening.

Choose **Russian – PC** (internally `RussianWin`, layout ID `19458`). Punctuation and `ё` then match the
keycaps. Likewise prefer **U.S.** over **ABC** for English — `ABC` is a slightly different layout that will
surprise you at some point.

System Settings → Keyboard → Input Sources → add *Russian – PC*, remove plain *Russian*.

## SD card reader

**Correction. An earlier version of this document said the reader works with `Sinetek-rtsx`. It does not,
and never did — no card had ever been inserted to check.** The claim is withdrawn; here is what is actually
true.

### Why Sinetek-rtsx cannot work here

The reader in the 9500 is a **Realtek RTS5260**:

```bash
ioreg -l -w0 | grep -oE '"IOName" = "pci10ec,[0-9a-f]+"' | sort -u
```

```
"IOName" = "pci10ec,5260"
```

`Sinetek-rtsx` 2.5 matches only these:

```
0x5209 0x5227 0x5229 0x522A 0x5249 0x5286 0x5287 0x5289 0x525A
```

No `5260`. So the kext loads, reports no error, and attaches to nothing — `ioreg -c RtsxPciChip` is empty.
Adding the device ID to `IOPCIMatch` does **not** help: the RTS5260 is a later generation with different
initialisation, and someone has already tried exactly that
([Sinetek-rtsx issue #17](https://github.com/cholonam/Sinetek-rtsx/issues/17)).

This is the trap worth remembering: **a kext that loads is not a kext that works.** Check what it attached
to, not whether it appears in `kmutil showloaded`.

### What does work

[RealtekCardReader](https://github.com/0xFireWolf/RealtekCardReader) 0.9.7 has a
`RealtekRTS5260Controller` personality matching `0x526010EC`.

```bash
sudo cp -R RealtekCardReader.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/RealtekCardReader.kext
sudo chmod -R 755 /Library/Extensions/RealtekCardReader.kext
sudo cp scripts/com.local.realtekcardreader.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.realtekcardreader.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.realtekcardreader.plist
```

The first load fails with

```
Extension with identifiers science.firewolf.rtsx not approved to load.
Please approve using System Settings.
```

That is expected for a kext loaded into a running system rather than injected by OpenCore. Approve it in
**System Settings → Privacy & Security** ("Allow"), restart, and it loads from then on.

Confirm it attached, rather than merely loaded:

```bash
ioreg -c RealtekRTS5260Controller -w0 | grep -c '+-o'     # must be 1
diskutil info disk4 | grep 'Device / Media Name'          # "Built In SDXC Reader"
```

Measured here: a 64 GB SDXC card detected, `Protocol: Secure Digital`, sustained read **23 MB/s**.

### Caveats, stated plainly

- 0.9.7 is beta, last updated **October 2022**, and the author lists support only up to Monterey. Sequoia is
  untested upstream. It read 52 GB of files without dropping here, but that is one machine and one session.
- 23 MB/s is well below what UHS-I should give (80–90 MB/s), so the driver is evidently not negotiating the
  faster bus modes.
- MMC and SD Express cards are not supported at all.
- `Sinetek-rtsx` can be removed from `/Library/Extensions` along with its LaunchDaemon — on this machine it
  can never match anything.

### If the card is detected but will not mount

Worth knowing, because it looks like a driver failure and is not one. A card formatted by a dash cam (or any
Linux `mkfs.fat`) can carry a FAT32 filesystem while the MBR partition **type byte** says `0x07`, meaning
NTFS:

```bash
sudo fdisk /dev/disk4
```

```
1: 07 ... HPFS/QNX/AUX
```

macOS trusts that byte and calls `ntfs.fs` — and **`mount_ntfs` no longer exists in Sequoia**, Apple removed
the read-only NTFS helper. The result is `Volume on disk4s1 failed to mount`. Mount it by hand instead:

```bash
sudo mkdir -p /Volumes/SDCARD
sudo mount -t msdos -o ro,noowners /dev/disk4s1 /Volumes/SDCARD
```

Or change the type byte to `0x0C` so Finder mounts it automatically — that writes one byte to the card, so
do it deliberately.
