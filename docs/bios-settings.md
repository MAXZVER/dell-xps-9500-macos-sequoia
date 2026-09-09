# BIOS settings

Dell's firmware on the XPS 15 9500 exposes fewer knobs than a desktop board, which is mostly good news —
there is less to get wrong.

## What to set

| Setting | Value | Why |
|---|---|---|
| **SATA Operation** | `AHCI` | `RAID On` hides the NVMe drive from macOS entirely. This is the single most common "the installer cannot see my disk" cause. |
| **Secure Boot** | Disabled | OpenCore is not signed by Microsoft's CA. |
| **Intel SGX** | Disabled | Not supported by macOS; leaving it on can cause boot issues. |
| **Fastboot** | `Thorough` | `Minimal` skips device initialisation that macOS expects. |
| **Wake on AC / Wake on Dock** | Disabled | Both cause spurious wakes from hibernation. |
| **Thunderbolt security** | No security, legacy boot support enabled | Needed for TB3 devices and display output. |
| **VT-d** | Either is fine | `DisableIoMapper` is enabled in `config.plist`, so macOS ignores it. |

## CFG Lock

You do not need to unlock it on this machine. Both `AppleCpuPmCfgLock` and `AppleXcpmCfgLock` are **disabled**
in this configuration, and native power management is confirmed working:

```bash
sysctl -n machdep.xcpm.mode      # → 1
```

`1` means XCPM is driving the CPU. If you get `0`, something is wrong — but on stock XPS 9500 firmware this
has not been observed.

## The sleep option — do not chase it

Some firmware builds expose a choice between **Modern Standby (S0ix)** and **S3**. It is tempting, because
macOS supports S3 and does not support S0ix.

**Switching it to S3 does not give you working sleep.** Tested directly on this machine: it enters sleep, and
on wake the fans spin up to a black screen and it never returns — you have to hold the power button. There is
no S3 resume path in this firmware regardless of what the setting claims.

Leave it alone and use hibernation instead — see [sleep and hibernation](sleep-hibernation.md), which is
reliable and fully solves the problem.

## Firmware updates

Updating Dell firmware is safe with OpenCore installed, but two notes:

- `run-efi-updater = No` is set in NVRAM so macOS never tries to touch the firmware itself.
- After a firmware update, **check your power-management settings**. Firmware updates can reset NVRAM, which
  takes `csr-active-config` and other persisted variables with it.

There is no BIOS whitelist or hidden variable that needs patching for this configuration. Attempts to extract
Dell's hidden setup variables from the firmware update package were made during this work and came to
nothing — the setup module is not in the distributed package. Do not spend time there.

## Battery

The stock battery is a **DELL M59JH06** (BYD cell), 7394 mAh design capacity. Replacing it does **not** affect
anything in NVRAM or your SMBIOS — the battery carries no configuration. After a replacement, confirm the
sensors still read correctly:

```bash
pmset -g batt
system_profiler SPPowerDataType | grep -E "Full Charge|Cycle Count|Condition"
```
