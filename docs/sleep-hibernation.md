# Sleep and hibernation

This is the hard part, and the reason this repository exists. If you only read one document, read this one.

## The short version

```bash
sudo pmset -a hibernatemode 25
sudo pmset -a standby 1
sudo pmset -a powernap 1
sudo pmset -a standbydelaylow 1
sudo pmset -a standbydelayhigh 1
sudo pmset -a womp 0
sudo pmset -a proximitywake 0
```

Close the lid → the machine writes a hibernation image and powers off. Open the lid → it resumes with your
session intact. Verified repeatedly, including a 37-minute hibernation.

Two things will silently break this. **Do not** set `standby 0` or `powernap 0`, and **do not** put
`rtcfx_exclude` in your boot arguments. Both are explained below, because both are things people are
routinely advised to do.

## Why S3 is not an option here

The XPS 15 9500 is a **Modern Standby (S0ix)** machine. It has no S3 sleep state that macOS can use:

- macOS has no S0ix support at all — it only knows S3 and S4.
- The Dell firmware exposes an S3 toggle in some builds, but flipping it does not give you a working S3:
  the machine enters sleep, and on wake the fans spin up to a black screen and never come back. There is
  no S3 resume path in the firmware. This was tested directly; it is not a configuration mistake.

So the only remaining option is **S4 — hibernation.** Write the whole of RAM to disk, cut power, restore on
boot. It is slower than S3 (a few seconds to write, a few to restore) but it is genuinely reliable, and on
a laptop that would otherwise drain its battery in "sleep", arguably better.

## What each setting does

| Setting | Value | Why |
|---|---|---|
| `hibernatemode` | `25` | Write the image, then **power off**. Do not keep RAM alive. Mode `3` (the default) keeps RAM powered and relies on S3 — useless here. |
| `standby` | `1` | Permission to enter standby (hibernation) at all. **With `0`, no image is ever written** and the machine just dies on lid close. |
| `standbydelaylow` / `standbydelayhigh` | `1` | Seconds of sleep before entering standby. `1` means "hibernate immediately", which is what you want when there is no working S3 to linger in. |
| `powernap` | `1` | Required for the standby transition to run its housekeeping. Turning it off was one of the two mistakes that made this look unsolvable. |
| `womp` | `0` | Wake-on-LAN off. It creates spurious wakes. |
| `proximitywake` | `0` | Needs Apple wireless hardware; off. |

On AC power this configuration also uses `sleep 0` — the machine does not idle-sleep while plugged in.
That is a preference, not a requirement; set `sudo pmset -c sleep <minutes>` if you want it to.

## The two traps

### 1. `standby 0` and `powernap 0`

A great deal of hackintosh advice says to disable standby and Power Nap to "fix" sleep problems. On this
machine that advice is exactly backwards: those two settings are what permit the hibernation image to be
written in the first place. With them off, closing the lid produces a machine that is off and cannot resume,
which reads like "hibernation does not work" when in fact hibernation was never attempted.

### 2. `rtcfx_exclude` in boot-args

`RTCMemoryFixup` is in this EFI, and it is genuinely useful — it stops the firmware from tripping over
macOS's RTC usage. But its `rtcfx_exclude` argument tells it to protect a range of RTC memory from being
written.

**macOS stores its "I am hibernating, resume from the image" marker in RTC memory.** Excluding the range
that contains it (`rtcfx_exclude=80-FF` is the range commonly recommended) means the marker never gets
written, so on power-up the firmware and macOS have no idea a hibernation image exists, and you get a
cold boot with your session gone.

If you have `rtcfx_exclude` anywhere in your boot arguments, remove it. Keep `RTCMemoryFixup` itself.

## Supporting pieces in the EFI

These are already configured in `EFI/OC/config.plist`; listed here so you know what to preserve.

**Kexts**
- `HibernationFixup.kext` — makes hibernation behave on non-Apple firmware
- `RTCMemoryFixup.kext` — RTC handling (without `rtcfx_exclude`, see above)

**boot-args**
- `hbfx-ahbm=3` — HibernationFixup's auto-hibernate bitmask. `3` is the value that works here; see the
  [HibernationFixup documentation](https://github.com/acidanthera/HibernationFixup) for the meaning of
  individual bits if you want to tune it.

**Misc → Boot**
- `HibernateMode` = `NVRAM` — OpenCore stores the wake signature in NVRAM

**Booter → Quirks**
- `DiscardHibernateMap` = `true`

**Kernel → Quirks**
- `DisableRtcChecksum` = `true` — stops the firmware invalidating RTC on every boot

**Kernel → Patch**
- `Disable RTC wake scheduling` on `com.apple.driver.AppleRTC` — enabled

**ACPI**
- `SSDT-RTC.aml` — RTC device definition
- `SSDT-PTSWAKTTS.aml` with the `_PTS → ZPTS` / `_WAK → ZWAK` patches — intercepts the sleep/wake methods
  so the vendor's own handling does not interfere

## Verifying it actually worked

Do not trust the machine coming back on — verify it hibernated rather than simply rebooting.

```bash
pmset -g log | grep -E "Sleep  |Wake  |DarkWake" | tail -10
```

A real hibernation cycle looks like this:

```
17:32:56 Sleep   Entering DarkWake state due to 'Clamshell Sleep': ...
17:33:26 Sleep   Entering Sleep state due to 'Clamshell Sleep': ... 68 secs
17:34:34 Wake    Wake from Standby [CDNVA] : due to XDCI/UserActivity Assertion
```

**`Wake from Standby` is the phrase that matters.** It means the session was restored from the hibernation
image. If you see `Wake from Normal Sleep`, the machine never hibernated; if you see no `Wake` line at all
and `uptime` is small, it cold-booted and you lost your session.

Also confirm the image is real:

```bash
ls -lh /var/vm/sleepimage
```

It should be several gigabytes and its timestamp should match your last sleep.

## One gotcha that will bite you later

**Changing SMBIOS resets `hibernatemode` to the default.** If you regenerate your serial numbers, change
`SystemProductName`, or otherwise touch `PlatformInfo`, macOS treats the machine as new hardware and
reverts the power management settings. Re-run the `pmset` block above afterwards, and re-verify — this cost
real time to rediscover.

## What sleep does to Bluetooth

Nothing — it survives. Verified: boot, sleep, wake on lid, Bluetooth still connected and pairing works.
A *reboot*, however, does break Bluetooth on this machine; see
[Wi-Fi and Bluetooth](wifi-and-bluetooth.md#bluetooth).
