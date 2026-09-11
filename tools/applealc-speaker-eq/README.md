# A 32-band equaliser inside the audio driver

The internal-speaker path of AppleALC's ALC289 layout 13 ships with a two-way crossover and no
equalisation. This adds a `DspEqualization32` in front of the crossover, which gives a **system-wide EQ
running inside AppleHDA** — every application, no virtual audio device, no interference with the volume keys.

| | |
|---|---|
| `layout13-speaker-eq.patch` | the layout change, as a `git apply` patch against AppleALC |
| `kmod_glue.c` | the `kmod_info` definition Xcode would have generated — without this the kext is silently rejected |
| `build.sh` | fetches sources, patches, regenerates resources, compiles and links. Command Line Tools only |

Read [docs/building-applealc-without-xcode.md](../../docs/building-applealc-without-xcode.md) before running
this. It documents the four traps, including the one that costs a boot.

## Use

```bash
./build.sh                  # -> ./out/AppleALC
```

Then replace the binary inside the kext bundle, keeping everything else — `Info.plist` in particular carries
the [woofer pin configuration](../../docs/woofers.md#a-the-pin-config-permanently):

```bash
D=/Volumes/EFI/EFI/OC/Kexts/AppleALC.kext/Contents/MacOS
sudo cp "$D/AppleALC" "$D/AppleALC.stock"
sudo cp out/AppleALC "$D/AppleALC"
sudo chmod 755 "$D/AppleALC"
```

Revert with `sudo cp "$D/AppleALC.stock" "$D/AppleALC"`. Type it out before rebooting.

## Verifying it took effect

Count the live DSP instances:

```bash
ioreg -l -w0 | grep -oE '"Dsp[A-Za-z0-9]+"=[0-9]+' | grep -v '=0$'
```

```
"DspFuncEQ"             = 2   ->  3      the new instance, on the speaker path
"DspParameter"          = 56  ->  60
"DspFunc2WayCrossover"  = 1              unchanged
```

The two pre-existing `DspFuncEQ` instances belong to the `Mic` and `LineIn` chains. A third one means the
speaker EQ instantiated.

## The curve

Derived from the speakers' own response, measured with three microphone positions averaged by power — see
[measuring speakers](../measure/README.md) for the method and [woofers.md](../../docs/woofers.md#measurements)
for the numbers.

| Band | Type | Frequency | Q | Gain | Why |
|---|---|---|---|---|---|
| 0 | high-pass | 110 Hz | 0.7071 | −3.01 dB | below this the cones move without producing sound |
| 4 | parametric | 170 Hz | 0.9 | **+8 dB** | the lowest range the woofers still answer in |
| 10 | parametric | 630 Hz | 2.0 | +4 dB | partial fill of a dip that is the same from every position |
| 18 | parametric | 1800 Hz | 1.0 | **−7 dB** | the 1.25–2 kHz rise; the most reliably measured feature |
| 24 | parametric | 7000 Hz | 0.7 | +4 dB | top end — **unverified**, this rig cannot measure up there |
| 31 | low-pass | 19000 Hz | 0.7071 | −3.01 dB | |

To change it, edit `BANDS` in [`set-eq.py`](set-eq.py) and run it against
`Resources/ALC289/layout13.xml`; it rewrites the `Filter` block in place, line by line, so the diff stays
readable instead of the whole file being reformatted by `plistlib`.

### Verified, not assumed

Measured with the EQ engaged and with a stock AppleALC, from the same microphone position, and compared
against what the filters should produce:

```
average error 0.7 dB, worst 2.2 dB   (rig repeats to +-1.5 dB)
```

The driver does what the curve says. What the curve *should* say is the harder question, and one earlier
answer was wrong: a −3 dB cut at 500 Hz, put there because a single-position measurement showed a peak.
Averaging three positions showed a **dip** of −4.9 dB. That band is gone.

Two residuals cannot be fixed by equalisation and are left alone:

- **200 Hz, −11 dB.** The driver is at its limit; the boost already raised distortion at 200 Hz from 2.1 %
  to 3.9 %. More gain buys distortion, not output.
- **630 Hz, −6 dB.** Consistent across every microphone position, which points at phase cancellation where
  the crossover hands over, not at a level problem. Filled only partially.

## The filter format

Worth documenting, because it is not written down anywhere and the input chains are the only reference. Each
entry in the `Filter` array of a `DspEqualization32` uses numeric keys:

| Key | Meaning |
|---|---|
| `2` | parameter-set id (`2` throughout the existing chains) |
| `3` | band index, 0–31 |
| `4` | channel (`0` = both) |
| `5` | filter type: `0` low-pass, `1` high-pass, `4` parametric |
| `6` | frequency — an IEEE-754 float **stored as its 32-bit integer bit pattern** |
| `7` | Q, same encoding |
| `8` | gain in dB, same encoding |

So 110.0 Hz is written as `1121714176` (`0x42DC0000`). Signed values come out negative in the plist:
−3.0103 dB is `-1069504319`. Convert with

```python
struct.unpack('<f', struct.pack('<i', value))[0]
```

Bands may be listed sparsely — unused indices are simply absent and pass through flat.
