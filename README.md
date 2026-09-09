# Dell XPS 15 9500 — macOS Sequoia (OpenCore)

A complete, working OpenCore configuration for the **Dell XPS 15 9500** (Comet Lake-H) running **macOS Sequoia 15.7.9**.

The headline result: **sleep works.** Not "sort of works" — the machine survives a closed lid, wakes on lid open, and keeps its session. On a Modern Standby laptop with no S3 resume path in firmware that is not obvious, and getting there took a lot of dead ends. Those dead ends are documented too, so you do not have to walk them again.

> 🇷🇺 Русская версия: **[README.ru.md](README.ru.md)** · документация в [`docs/ru/`](docs/ru/)

---

## Status

| Component | State | Notes |
|---|---|---|
| **Sleep / wake** | ✅ Works | S4 hibernation, wake on lid open — [details](docs/sleep-hibernation.md) |
| CPU power management | ✅ Works | `XCPM` active, native speed stepping |
| Intel UHD 630 | ✅ Works | Full QE/CI, brightness keys, external display |
| NVIDIA GTX 1650 Ti | ⛔ Disabled | No macOS driver exists — powered off to save battery |
| Internal display 1920×1200 | ✅ Works | |
| External display (HDMI / USB-C) | ✅ Works | See [graphics](docs/graphics-and-display.md) |
| Audio — speakers, headphones | ✅ Works | AppleALC `layout-id 13` |
| Audio — internal microphone | ✅ Works | Needs a small helper, see [audio](docs/audio-keyboard-cardreader.md) |
| **Wi-Fi** | ✅ Works | Intel AX201 via `itlwm` + HeliPort |
| Wi-Fi — native macOS menu | ⛔ Not achievable | Requires OCLP root patching — [why](docs/wifi-and-bluetooth.md) |
| **Bluetooth** | ✅ Works | Intel, incl. audio devices — [one caveat](docs/wifi-and-bluetooth.md#bluetooth) |
| USB 3 / Type-C / Thunderbolt 3 | ✅ Works | Mapped, 15-port limit respected |
| Trackpad (I²C, gestures) | ✅ Works | VoodooI2C |
| Keyboard, brightness/volume keys | ✅ Works | VoodooPS2 |
| SD card reader | ✅ Works | Sinetek-rtsx |
| Battery status, sensors, fans | ✅ Works | VirtualSMC + SMCDellSensors |
| Webcam | ✅ Works | |
| Fingerprint reader | ⛔ Never | No macOS driver, no prospect of one |
| AirDrop / Handoff / Continuity | ⛔ Never | Requires Apple wireless hardware |
| iCloud, App Store | ✅ Works | Do **not** enable Find My Mac — [why](docs/smbios.md#apple-id) |

---

## Hardware this was built and tested on

| | |
|---|---|
| Model | Dell XPS 15 9500 |
| CPU | Intel Core i5-10300H (Comet Lake-H, 4C/8T) |
| iGPU | Intel UHD Graphics 630 — `0x3E9B`, platform-id `0x3E9B0009` |
| dGPU | NVIDIA GeForce GTX 1650 Ti (disabled) |
| RAM | 16 GB |
| Display | 1920×1200 (FHD+), non-touch |
| Storage | Samsung SSD 970 EVO Plus 1 TB (NVMe) |
| Wi-Fi / BT | Intel Wi-Fi 6 AX201 — `pci8086,6f0`, subsystem `1651` (CNVi) + Intel BT `8087:0026` |
| Audio | Intel Smart Sound (cAVS), AppleALC `layout-id 13` |
| Thunderbolt | Intel JHL7540 Titan Ridge |
| Battery | DELL M59JH06 (BYD), 7394 mAh design |

If your 9500 has an i7, a 4K OLED panel or a different Wi-Fi card, most of this still applies — but read
[graphics](docs/graphics-and-display.md) and [SMBIOS](docs/smbios.md) before copying anything.

**Software:** OpenCore `1.0.7` (REL-107-2025-11-19) · macOS Sequoia `15.7.9` (24G830) · SMBIOS `MacBookAir9,1`

---

## Quick start

> Read [SMBIOS](docs/smbios.md) first. Booting this EFI unmodified will not work — the serial fields are
> deliberately blanked out.

1. Copy `EFI/` to the ESP of your target disk.
2. Generate your own SMBIOS identity and fill in `SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM` —
   see [SMBIOS](docs/smbios.md). `ROM` must be your real onboard NIC MAC address.
3. Set the BIOS up as described in [BIOS settings](docs/bios-settings.md).
4. Boot the macOS installer, install, then apply the [sleep configuration](docs/sleep-hibernation.md) —
   it is a set of `pmset` commands, and macOS does **not** apply them for you.
5. Optional quality-of-life pieces: [`scripts/`](scripts/) and [`tools/`](tools/).

The shipped boot arguments include `-v keepsyms=1 debug=0x100`, which give you verbose boot and useful panic
output. They are deliberate — this configuration was developed with them. Once everything works, drop them
for a normal graphical boot; keep `-igfxblt hbfx-ahbm=3 -btlfxallowanyaddr`, which are functional.

### What is deliberately missing from this repo

`IOSkywalkFamily.kext`, `IO80211FamilyLegacy.kext` and `AirPortBrcmNIC.kext` are **Apple's proprietary
binaries** extracted from an older macOS. Other repositories ship them; this one does not, because
redistributing them is copyright infringement. They are only needed for the native-Wi-Fi route, which
[does not work without OCLP root patching anyway](docs/wifi-and-bluetooth.md#native-airportitlwm).
`AirportItlwm.kext` is likewise not shipped — get it from
[OpenIntelWireless releases](https://github.com/OpenIntelWireless/itlwm/releases).

---

## Documentation

| | |
|---|---|
| [Sleep and hibernation](docs/sleep-hibernation.md) | **Start here.** The one genuinely hard problem, and how it was solved |
| [Wi-Fi and Bluetooth](docs/wifi-and-bluetooth.md) | Why `itlwm`, why native AirportItlwm is a dead end, Bluetooth quirks |
| [Graphics and display](docs/graphics-and-display.md) | Framebuffer patches, disabling the dGPU, external monitors |
| [USB mapping](docs/usb-mapping.md) | The port map and how it was built |
| [Audio, keyboard, card reader](docs/audio-keyboard-cardreader.md) | Smaller fixes, including a Russian-layout annoyance |
| [SMBIOS and Apple ID](docs/smbios.md) | Serial coherence, board-ID check, what to avoid |
| [BIOS settings](docs/bios-settings.md) | What to change in Dell firmware |
| [Known issues](docs/known-issues.md) | What does not work and what was ruled out |
| [Troubleshooting](docs/troubleshooting.md) | How to diagnose, with real log signatures |

---

## Credits

- [Acidanthera](https://github.com/acidanthera) — OpenCore, Lilu, VirtualSMC, WhateverGreen, AppleALC and much else
- [OpenIntelWireless](https://github.com/OpenIntelWireless) — `itlwm`, `HeliPort`, `IntelBluetoothFirmware`
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) — the OpenCore install guide
- [zhen-zen/XPS-9500-CometLake-OpenCore](https://github.com/zhen-zen) and the wider XPS 9500 community — the
  base configuration this work started from
- [5T33Z0/OCLP4Hackintosh](https://github.com/5T33Z0/OCLP4Hackintosh) — the clearest write-up of the Sequoia
  Wi-Fi situation

## License

Configuration, documentation and scripts in this repository: [MIT](LICENSE).

Bundled kexts belong to their respective authors and carry their own licenses — see each `.kext`.
