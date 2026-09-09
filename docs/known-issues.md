# Known issues and things that were ruled out

The value of this list is mostly negative knowledge: time you do not have to spend.

## Will never work

| | Why |
|---|---|
| **NVIDIA GTX 1650 Ti** | No macOS driver for Turing, and none is coming. The card is disabled deliberately. |
| **Fingerprint reader** | No driver, no reverse-engineering effort worth the name. |
| **AirDrop, Handoff, Continuity, Sidecar, Universal Control** | Require Apple's own wireless hardware. No Intel card can do these, patched or not. |
| **S3 sleep** | No resume path in the firmware — see [BIOS settings](bios-settings.md#the-sleep-option--do-not-chase-it). Hibernation replaces it and works. |

## Works, with a caveat

### Bluetooth does not survive a reboot

`shutdown -r now` leaves the Intel controller dead. A full power-off and power-on fixes it. Hibernation is
fine, because it cuts power anyway. Full detail, including how to tell "dead" from "switched off", is in
[Wi-Fi and Bluetooth](wifi-and-bluetooth.md#the-one-caveat-it-does-not-survive-a-reboot).

### Wi-Fi is not native

`itlwm` + HeliPort. It works well, but the network comes up after login and appears as an Ethernet service.
The native route needs OCLP root patching — [the full analysis](wifi-and-bluetooth.md#native-airportitlwm).

### Microphone needs a helper

Not a driver problem — `coreaudiod` picks the wrong default input. See
[audio](audio-keyboard-cardreader.md#the-microphone-problem).

### Battery life is modest

Around 13–14 W at idle with the screen on. With a healthy battery that is roughly 6 hours; with a worn one,
proportionally less. The dGPU being powered off is already accounted for in that figure.

Check your battery's real state before blaming the configuration:

```bash
system_profiler SPPowerDataType | grep -E "Full Charge Capacity|Cycle Count|Condition"
```

Against a 7394 mAh design capacity, a reading in the 4000s means the cell is worn, not that macOS is
mismanaging power.

## Ruled out — do not re-investigate

These were investigated during this work and are dead ends. Each cost hours.

**`rtcfx_exclude` does not need tuning — it needs removing.** It breaks hibernation by blocking the RTC wake
marker. Whatever range you pick, do not use it here.

**`standby 0` / `powernap 0` do not fix sleep.** They prevent the hibernation image from being written, which
is the opposite of a fix. Widely recommended, wrong on this machine.

**`XhciPortLimit` does not fix USB.** Broken since macOS 11.3. Build a proper port map instead —
[USB mapping](usb-mapping.md).

**USB breakage on macOS Tahoe is not your port map.** The identical EFI works on Sequoia. It was an Apple
driver regression. A great deal of time was spent re-deriving a map that was already correct.

**The `IOName = pci14e4,43a0` spoof does not enable native Wi-Fi.** It exists so OCLP will apply Broadcom
root patches, and is meant to be removed afterwards. On its own it changes nothing — tested.

**A different `AirportItlwm` build is not the answer to "no networks found".** The kexts were verified
byte-identical (SHA-256) to a reference configuration that reports success. The blocker is the userspace
stack, not the driver.

**Dell's firmware update package does not contain the setup module.** You cannot extract hidden BIOS
variables from it. `UEFIExtract` / `IFRExtractor` on the PFS container will not give you what you want.

**macOS has no process-snapshot facility.** There is no CRIU equivalent; you cannot dump and restore running
applications to work around sleep. Hibernation is the supported answer and it works.

## Housekeeping

If you have been experimenting, the ESP tends to accumulate `config-*.plist` backups — this machine had
about fifty. They are harmless but make the EFI hard to read. Keep two or three known-good ones and delete
the rest.
