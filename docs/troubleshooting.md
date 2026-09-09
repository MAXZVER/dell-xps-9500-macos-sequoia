# Troubleshooting

Concrete commands and real log signatures, rather than general advice.

## Read the log from a *previous* boot

The single most useful trick here. macOS's unified log persists across reboots, so when a change leaves the
machine without network or otherwise unreachable, you can boot back into a working configuration and read
what happened during the failed boot:

```bash
log show --style compact \
  --start "2026-09-09 16:22:00" --end "2026-09-09 16:36:00" \
  --predicate 'process == "airportd"' | head -60
```

This is how the Wi-Fi problem was diagnosed without ever having a working shell on the failing boot.

Useful predicates:

```bash
# kext loading
log show --last 5m --style compact | grep "Received kext load notification"

# a specific driver
log show --last 5m --style compact --predicate 'senderImagePath CONTAINS "AirportItlwm"'

# 802.11 ioctl failures, grouped
log show --last 5m --style compact \
  | grep -oE "IOCTL type [0-9]+/'[A-Z0-9_]+' return -?[0-9]+" | sort | uniq -c | sort -rn
```

## Sleep

```bash
pmset -g custom                                    # what is actually set
pmset -g log | grep -E "Sleep  |Wake  |DarkWake"   # what actually happened
ls -lh /var/vm/sleepimage                          # is there a hibernation image
```

Look for **`Wake from Standby`**. Anything else means it did not hibernate. See
[sleep and hibernation](sleep-hibernation.md#verifying-it-actually-worked).

## Bluetooth

```bash
system_profiler SPBluetoothDataType | grep -E "Address|State|Firmware"
ioreg -r -c IntelBluetoothFirmware -w0 | head -3
log show --last 5m --style compact | grep "selected configuration"
```

`Firmware Version` is the field that tells you the truth — `v256 c256` means alive, `v0` means dead. And
**wait at least two minutes after boot** before judging; the firmware upload starts around 30 seconds in.

## Kexts

```bash
kmutil showloaded | grep -v com.apple          # third-party kexts actually loaded
ioreg -r -c <ClassName> -w0 | head -5          # did a driver attach?
```

In `ioreg` output, `!registered, !matched` on a driver instance means it loaded but never bound to a device.
That distinction matters: "the kext is loaded" and "the driver is driving something" are different claims.

## Mounting the EFI partition

```bash
ESP=$(diskutil list internal physical | awk '/EFI/{print $NF}' | head -1)
sudo mkdir -p /Volumes/ESP
sudo mount -t msdos /dev/$ESP /Volumes/ESP
```

Do **not** hardcode `disk0s1`. With a USB installer plugged in, disk numbering shifts and you will silently
edit the wrong ESP — or nothing at all. Deriving it from `diskutil list internal physical` is reliable.

If `mount` returns `Resource busy`, it is already mounted; find where:

```bash
mount | awk -v d="/dev/$ESP" '$1==d{print $3}'
```

## Editing config.plist from the command line

`PlistBuddy` is awkward for arrays. Python is better and is available once Command Line Tools are installed:

```bash
xcode-select --install     # /usr/bin/python3 is a stub without this
```

```python
import plistlib
c = plistlib.load(open('/Volumes/ESP/EFI/OC/config.plist','rb'))
for e in c['Kernel']['Add']:
    if e['BundlePath'] == 'itlwm.kext':
        e['Enabled'] = False
plistlib.dump(c, open('/Volumes/ESP/EFI/OC/config.plist','wb'))
```

Always `plutil -lint` the result before rebooting.

> **If you are writing shell scripts for the Mac from a Windows box:** Python's text mode there emits CRLF,
> and bash will not run the result. Symptoms are misleading — `syntax error near unexpected token` on a line
> that is obviously fine, and matching checksums on both ends because the file was broken before it was sent.
> Run `sed -i 's/\r$//' script.sh && bash -n script.sh`, and check `bash -n` again on the Mac.

## LaunchDaemons that will not start

```bash
sudo launchctl kickstart -p system/com.local.example
sudo launchctl print system/com.local.example | grep -E 'state|last exit'
cat /var/log/<your StandardErrorPath>
```

Two things that catch people:

- Use `launchctl bootstrap` / `bootout`, not the deprecated `load` / `unload` — the latter fails with an
  uninformative `Load failed: 5`.
- A daemon that runs **your own script** should invoke it through a signed binary:
  `ProgramArguments = ["/bin/bash", "/usr/local/bin/your-script.sh"]`. Pointing straight at the script can
  fail with `EX_CONFIG (78)`.

And test the daemon the way the system will run it. A script that works under `sudo bash script.sh` can still
fail under launchd, for reasons that have nothing to do with your logic.

## Recovery

Keep a USB stick with a known-good OpenCore on it. If a change to the internal EFI leaves the machine
unbootable or without network, press **F12** at power-on and boot from the stick.

Note that with the stick inserted, the machine may boot *from it* by default — which silently masks changes
you made to the internal ESP. If an edit seems to have had no effect, check which ESP you actually booted:

```bash
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version
diskutil list external physical
```
