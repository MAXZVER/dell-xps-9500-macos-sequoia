# SMBIOS and Apple ID

## Why MacBookAir9,1

`MacBookAir9,1` is a 2020 MacBook Air with a 10th-generation (Ice Lake) CPU and Intel graphics only. It is
the closest supported model to a quad-core Comet Lake laptop with a UHD 630 and no usable discrete GPU, and
it gives sane power-management and graphics defaults.

`MacBookPro16,x` alternatives all imply a discrete AMD GPU, which this machine does not have.

## Generating your identity — required

The shipped `config.plist` has these fields deliberately blanked:

```
SystemSerialNumber = CHANGEME
MLB                = CHANGEME
SystemUUID         = 00000000-0000-0000-0000-000000000000
ROM                = 00 00 00 00 00 00
```

**It will not boot correctly until you fill them in.** Do not use values from any repository, this one
included — a duplicated serial is worse than a random one.

Use [macserial](https://github.com/acidanthera/OpenCorePkg/releases) (ships with OpenCore, in `Utilities/macserial`):

```bash
macserial -m MacBookAir9,1 -n 1
```

It prints a matching serial and MLB pair. Then:

| Field | Value |
|---|---|
| `SystemSerialNumber` | the serial from `macserial` |
| `MLB` | the board serial from the same line — **they must be a matched pair** |
| `SystemUUID` | any random UUID (`uuidgen`), just make it unique to you |
| `ROM` | **your real onboard NIC MAC address**, as 6 raw bytes |

`ROM` matters. Apple services derive part of their device identity from it, and a value that does not match
your actual hardware is a common cause of iServices failures. Read it with `ifconfig` on the built-in
Ethernet or Wi-Fi interface.

### Check that the serial is not a real Mac's

Paste your generated serial into [Apple's coverage page](https://checkcoverage.apple.com/). You want it to
be rejected as **invalid**. If Apple recognises it, it belongs to a real machine — generate another one.

## The board-ID check

Newer macOS refuses to install on some SMBIOS models. Rather than `-no_compat_check`, this configuration
uses the clean route, already set in `config.plist`:

- `Booter → Patch → "Skip Board ID check"` — **enabled**
- `NVRAM → 4D1FDA02-… → revpatch = auto,sbvmm` with `RestrictEvents.kext`

`SecureBootModel` is `Disabled`.

## A subtlety about NVRAM values

OpenCore's `NVRAM → Add` only writes a variable **if it does not already exist**. Variables listed under
`NVRAM → Delete` are cleared first and therefore re-applied every boot; everything else persists from
whatever was set before.

This bites people with `csr-active-config`. It is *not* in the `Delete` list here, so editing it in
`config.plist` changes nothing on a machine that already has a value in NVRAM. To actually change SIP you
must either add the key to `NVRAM → Delete` or reset NVRAM.

Worth checking what you really have:

```bash
nvram csr-active-config
csrutil status
```

## Apple ID

**iCloud, the App Store and system updates work.** Mail, Drive, Notes, Photos — all fine.

**Do not enable Find My Mac.** On real hardware it arms an activation lock tied to the machine's identity.
On a hackintosh it cannot work as intended and can write lock state into NVRAM. There is nothing to gain
and a real way to lose.

**iMessage and FaceTime are unreliable** on Intel-Wi-Fi hackintoshes and often refuse to activate. Repeated
failed activation attempts are one of the things that gets Apple IDs flagged. If you want to try, use a
secondary Apple ID rather than your primary one, and do not keep retrying.

## After changing SMBIOS, re-do two things

Changing serials makes macOS treat the machine as new hardware:

1. **Power management resets.** Re-apply the whole [sleep configuration](sleep-hibernation.md) and verify it.
2. **Bluetooth preference cache is invalidated.** Delete `/Library/Preferences/com.apple.Bluetooth.plist`
   and the matching `~/Library/Preferences/ByHost/com.apple.Bluetooth.*.plist`, then power off fully.

Both were discovered the slow way.
