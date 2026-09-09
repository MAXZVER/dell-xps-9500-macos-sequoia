# USB mapping

macOS refuses to enable more than 15 USB ports per controller. The XPS 9500's XHCI controller declares 17,
so without a port map some ports simply do not work — and which ones is essentially arbitrary.

`XhciPortLimit` is **not** the answer. It has been broken since macOS 11.3 and is disabled in this
configuration. The correct fix is a static port map, which is what `USBMap.kext` provides.

## The map

```
Controller 8086:06ED (XHC14)          model = MacBookAir9,1, port-count = 17
    HS03    port 3    UsbConnector 10     USB-A / Type-C data
    HS02    port 4    UsbConnector 10
    HS01    port 5    UsbConnector 10     ← Bluetooth lives here
    'HS08 ' port 11   UsbConnector 255    internal
    'HS07 ' port 14   UsbConnector 255    internal
    SS03    port 17   UsbConnector 10

Controller 8086:15EC                  model = MacBookAir9,1, port-count = 4
    SS02    port 3    UsbConnector 10
    SS01    port 4    UsbConnector 10
```

`UsbConnector 10` is USB 3 Type-A/Type-C; `255` marks an internal device that is not user-accessible.

### Yes, `HS07 ` and `HS08 ` really do have a trailing space

That is not a typo in this repository, and it is not a typo you should "fix". Those keys come from the
original working map for this machine and the trailing space is part of them. It was removed once during
development on the assumption that it was a mistake; nothing improved, and it was put back to stay
byte-identical to a known-good configuration. Leave it alone.

## Bluetooth sits on an unmapped-looking port

The Bluetooth controller enumerates at `Location ID 0x14500000`, which is port 5 — `HS01`, declared as
`UsbConnector 10` (external) rather than `255` (internal). That is why System Information calls it
`THIRD_PARTY_DONGLE`.

It is cosmetic. Bluetooth works. Changing it to `255` was considered and rejected: the reference
configuration for this laptop has it exactly this way, and there was no problem to solve.

## If your machine differs

Port maps are per-machine — different chassis revisions and different port populations produce different
maps. If USB devices are dead on some ports, build your own with
[USBToolBox](https://github.com/USBToolBox/tool) (works from Windows, which is convenient here) or
[USBMap](https://github.com/corpnewt/USBMap) from macOS, and replace
`EFI/OC/Kexts/USBMap.kext/Contents/Info.plist`.

## A word of warning from experience

If USB breaks after a macOS upgrade, suspect the OS before suspecting your map. On macOS Tahoe this exact
configuration lost most USB functionality; the same EFI on Sequoia works correctly. That was an Apple driver
regression, not a mapping error — and a lot of time went into re-deriving a map that had been right all
along.
