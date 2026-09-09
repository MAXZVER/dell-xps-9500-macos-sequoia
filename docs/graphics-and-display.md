# Graphics and display

## Intel UHD 630 (the one that matters)

```
PciRoot(0x0)/Pci(0x2,0x0)
    AAPL,ig-platform-id              = 09 00 9B 3E     → 0x3E9B0009
    device-id                        = 9B 3E 00 00     → 0x3E9B
    enable-backlight-registers-fix   = 01 00 00 00
```

Plus `WhateverGreen.kext` and `-igfxblt` in boot-args.

`0x3E9B0009` is the mobile UHD 630 framebuffer with three external connectors. It gives full acceleration,
a working internal panel at 1920×1200, and working external output. `enable-backlight-registers-fix`
together with `-igfxblt` is what makes the internal panel's backlight controllable on Comet Lake — without
it you get either a black panel or brightness stuck at one level.

Brightness keys come from `BrightnessKeys.kext` and `SSDT-PNLF-CFL.aml`.

### If you have the 4K OLED panel

This configuration was built and tested on the **1920×1200 non-touch** panel. The 4K OLED model usually
needs different framebuffer connector patching (and often `enable-dpcd-max-link-rate-fix`). Start from
[WhateverGreen's FAQ](https://github.com/acidanthera/WhateverGreen/blob/master/Manual/FAQ.IntelHD.en.md)
rather than assuming these values transfer.

## NVIDIA GTX 1650 Ti — disabled

```
PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)
    disable-gpu = 01 00 00 00
```

together with `SSDT-NoHybGfx.aml`.

There is no macOS driver for Turing GPUs and there never will be — NVIDIA support ended with Kepler. The card
is therefore powered down rather than left idling, which is worth a noticeable amount of battery life. Nothing
is lost: the iGPU drives every display on this machine.

## External displays

External output over HDMI and USB-C/Thunderbolt works.

One quirk shows up on this hardware: after sleep/wake or hot-plug, an external display can come back with a
wrong mode or not light up at all. `tools/displayfix.swift` is a small helper for that — it inspects the
current display configuration and can re-apply a sane mode:

```bash
swiftc -O tools/displayfix.swift -o ~/tools/displayfix
~/tools/displayfix              # report current state
~/tools/displayfix --autofix    # detect and correct
```

`scripts/com.local.displayguard.plist` runs it with `--autofix` in the background. Install it as a
LaunchAgent (edit the paths first — they contain a `YOUR_USERNAME` placeholder):

```bash
cp scripts/com.local.displayguard.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.local.displayguard.plist
```

Use `launchctl bootstrap`, not the deprecated `launchctl load` — on recent macOS the latter fails with an
unhelpful `Load failed: 5`.

## Thunderbolt 3

`SSDT-TB3_JHL7540TitanRidge.aml` and `SSDT-TB3HotPlug.aml` cover the Titan Ridge controller, with the
`NTFY → XFTY` ACPI patch for hot-plug. Display output and USB over Type-C work.
