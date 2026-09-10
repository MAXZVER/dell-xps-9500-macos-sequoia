# Wi-Fi and Bluetooth

The card is an **Intel Wi-Fi 6 AX201** — `pci8086,6f0`, subsystem `1651`, sitting on the CNVi interface at
`PciRoot(0x0)/Pci(0x14,0x3)`. Bluetooth is the Intel half of the same module, presented over USB as
`8087:0026`.

## Wi-Fi

Wi-Fi runs on **`itlwm.kext` + [HeliPort](https://github.com/OpenIntelWireless/HeliPort)**. This works, it is
stable, and it is what this configuration ships.

`itlwm` presents the wireless card to macOS as an *Ethernet* interface and does its own association. HeliPort
is the menu-bar client that drives it. Consequences worth knowing:

- The network service in System Settings is called **Ethernet**, not Wi-Fi. That is correct, not a bug.
- HeliPort is a user application, so **the network comes up after login**, not at the login window.
- Location services that rely on Wi-Fi scanning do not work, so no automatic time zone from Wi-Fi.
- Captive portals (hotels, airports) are not detected automatically — open the login page yourself.

`scripts/com.heliport.autostart.plist` starts HeliPort at login and keeps it running.

### Native AirportItlwm

There is a well-known route to make Wi-Fi appear as *real* macOS Wi-Fi: inject a downgraded network stack
(`IOSkywalkFamily` + `IO80211FamilyLegacy` from an older macOS), block the system's `IOSkywalkFamily`, and
load `AirportItlwm.kext` against the legacy family.

**On Sequoia this does not work by kext injection alone.** This was tested thoroughly here, so you do not
have to:

The injection part succeeds completely. All three kexts load without a single AMFI complaint, the driver
attaches (`CNVW@14,3/AirportItlwm/AirportItlwmInterface`), and `networksetup -listallhardwareports` reports a
genuine `Hardware Port: Wi-Fi`. Everything looks right.

Then it finds zero networks, and the Wi-Fi menu shows a nonsense message about needing an 802.1X profile.
The log says exactly why:

```
IOCTL type 207/'APPLE80211_IOC_CHANNELS_INFO' return -3900     (≈160× per boot)
IOCTL type 11/'APPLE80211_IOC_SCAN_RESULT'    return -1
Apple80211Scan Failed, err[22]   scanResultsCount=0
```

The driver never reports its supported channel list, so macOS cannot construct a scan request and gets
`EINVAL`. Scanning does not fail — **it never starts.** The 802.1X message is just the UI's fallback when the
driver has not told it which security types are supported.

The cause is that Sequoia's *userspace* Wi-Fi stack — `airportd` and CoreWLAN — is the new Skywalk-based one
and cannot talk to a legacy driver. Replacing the kexts is only half the job; the userspace half is what
**OCLP root patching** replaces. Both major guides on this say so explicitly:

- [5T33Z0/OCLP4Hackintosh — AirportItlwm on Sequoia](https://github.com/5T33Z0/OCLP4Hackintosh/blob/main/Enable_Features/AirportItllwm_Sequoia.md)
- [sap24601 — Native Wi-Fi on macOS Sequoia](https://github.com/sap24601/Native-Wifi-for-Hackintoshes-with-Intel-Wireless-cards-on-macOS-sequoia)

This also explains a detail you will find in other XPS 9500 configs and may be tempted to copy:

```xml
PciRoot(0x0)/Pci(0x14,0x3)
    IOName = pci14e4,43a0
```

That spoofs the Intel card as a Broadcom one — **not** to make the driver work, but so that OCLP agrees to
apply its Broadcom root patches. It is meant to be removed after patching. On its own it changes nothing;
tested, no effect.

### Should you do the OCLP route?

It is a real option, and it is reversible — OCLP does not modify the sealed system snapshot, it builds a new
one alongside and boots that. "Revert Root Patches" switches back, and a macOS update wipes the patches by
itself.

The costs are real too:

- SIP must be lowered to `csr-active-config = 03080000`.
- FileVault must be off.
- **Every macOS update removes the patches and takes Wi-Fi with them** until you re-apply.
- AirportItlwm has no WPA3, and reconnection after wake is reportedly unreliable — on a machine where sleep
  was hard-won, that is a real risk.

What you gain is the native Wi-Fi menu, networking at the login window, and Wi-Fi location services. You do
**not** gain speed — `itlwm` and `AirportItlwm` share the same driver core, version for version. And AirDrop,
Handoff and Continuity remain impossible regardless, because they need Apple's wireless hardware.

This configuration stays on `itlwm` + HeliPort. Your call may differ; now you can make it with the facts.

### Hiding the leftover Wi-Fi icon

If you experiment with AirportItlwm and go back, macOS may keep a stale network service of type `AirPort` and
leave a Wi-Fi icon with an exclamation mark in the menu bar. Restore your pre-experiment
`/Library/Preferences/SystemConfiguration/{preferences,NetworkInterfaces}.plist` (back them up first), and if
the icon persists:

```bash
defaults -currentHost write com.apple.controlcenter WiFi -int 8
defaults write com.apple.controlcenter 'NSStatusItem Visible WiFi' -bool false
killall -9 ControlCenter
```

Both keys are needed. `NSStatusItem Visible` alone gets overwritten by ControlCenter on every restart.

## Bluetooth

Bluetooth works — including audio devices. Kexts: `IntelBluetoothFirmware`, `IntelBTPatcher`,
`BlueToolFixup`, plus `-btlfxallowanyaddr` in boot-args and these NVRAM entries (already in the config, and
listed in `NVRAM → Delete` so they are reset every boot):

```
bluetoothExternalDongleFailed     <00>
bluetoothInternalControllerInfo   <0000000000000000000000000000>
```

### If Bluetooth is not up yet, give it time

The Intel controller can take a while to initialise. **How to tell a slow start from a real failure — look at
`Firmware Version`, not `State`:**

```
working:            Address: XX:XX:XX:XX:XX:XX   State: On    Firmware: v256 c256
just switched off:  Address: NULL                State: Off   Firmware: v256 c256
firmware not up:    Address: NULL                State: Off   Firmware: v0
```

`v256 c256` means the firmware uploaded and the controller is alive — `Address: NULL` then simply means
Bluetooth is toggled off in Control Center. **`v0` means the firmware has not been uploaded yet.** In that
state the log contains no `IOUSBHostDevice@…: IntelBluetoothFirmware selected configuration 1` line, and
`ioreg -r -c IntelBluetoothFirmware` shows `!registered, !matched`.

**Measure late, not early.** After a cold boot the firmware upload starts at roughly 30 seconds of uptime and
`State: On` follows up to a minute later. Judging it before then produces a false "it is broken" — that
happened repeatedly while writing this.

During development one warm reboot left the controller at `v0` for the three minutes it was observed, which
led to an earlier claim here that Bluetooth does not survive a reboot. **That claim was withdrawn** — the
machine's owner reports it does come up after a normal reboot, and a three-minute window was not long enough
to conclude otherwise. If yours is at `v0` well past that, a full power-off and power-on is a reliable way to
get it back.

Sleep is not a problem either way: hibernation cuts power, so waking is equivalent to a cold start.

`Chipset: THIRD_PARTY_DONGLE` and `Vendor ID: 0x004C (Apple)` in System Information are just how BlueToolFixup
presents the controller. Not a fault.

### If Bluetooth breaks after an SMBIOS change

Different failure, same symptom. Changing serial numbers invalidates the Bluetooth preference cache. Fix:

```bash
sudo rm -f /Library/Preferences/com.apple.Bluetooth.plist
rm -f ~/Library/Preferences/ByHost/com.apple.Bluetooth.*.plist
sudo shutdown -h now      # full power-off, not a reboot
```
