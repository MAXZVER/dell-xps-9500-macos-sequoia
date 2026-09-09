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

`Sinetek-rtsx.kext` drives the Realtek reader. It is present in `EFI/OC/Kexts` **and** installed to
`/Library/Extensions`, with a LaunchDaemon that loads it at boot:

```bash
sudo cp -R EFI/OC/Kexts/Sinetek-rtsx.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/Sinetek-rtsx.kext
sudo cp scripts/com.local.cardreader.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.cardreader.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.cardreader.plist
```

The daemon simply runs `kmutil load -p /Library/Extensions/Sinetek-rtsx.kext`. Logs go to
`/var/log/cardreader.log` — check there if a card does not mount.

This driver is a community reimplementation and is not as robust as a vendor driver. Treat it as
best-effort: it reads ordinary SD cards, but do not rely on it for anything critical.
