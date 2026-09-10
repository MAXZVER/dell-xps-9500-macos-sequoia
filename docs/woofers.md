# Enabling the woofers

The XPS 15 9500 has four speakers: two tweeters and two woofers. Out of the box on macOS you only get the
tweeters, which is why the machine sounds thin and people describe it as having "no bass".

This is fixable, and the fix is not a workaround — the woofers are on the same codec and simply need to be
switched on.

## What is actually wrong

The codec is a Realtek **ALC289**. Dumping its pin configuration shows:

| Node | Pin config | Meaning | Capabilities |
|---|---|---|---|
| `0x14` | `0x90170110` | Fixed / Speaker | PresenceDetect, **OUT**, **EAPD** |
| `0x17` | `0x411111F0` | **not used** | PresenceDetect, HeadphoneDrive, **OUT** |
| `0x1b` | `0x411111F0` | not used | OUT, IN, EAPD |
| `0x21` | `0x01211020` | Jack / Headphone | OUT, EAPD |

Node `0x14` drives the tweeters. Node **`0x17` drives the woofers** — but Dell's firmware declares it
unused, so macOS never touches it. Linux has the same problem and
[fixes it with a pin-config quirk](https://github.com/makeitmakesencethen/dell-xps-15-9500-linux-audio),
rewriting `0x17` from `0x411111f0` to `0x90170130`.

There is no separate amplifier chip involved. It is one codec, one missing pin definition.

## What does not work

**Injecting `PinConfigurations` through `DeviceProperties` has no effect.** It looks like it should — the
property exists in the IORegistry — but AppleHDA reads the pin defaults straight from the codec and ignores
the injected value. Verified: after a reboot with the property set, `0x17` still read back `0x411111F0`.

**Changing the AppleALC layout does not help either.** AppleALC's `Resources/ALC289/` contains only DSP
graph definitions (`layoutNN.xml`, `PlatformsNN.xml`) — there is no `ConfigData`, so AppleALC never sends
pin-configuration verbs for this codec at all. Layout 13 and layout 93 are both XPS 9500 profiles and
neither enables `0x17`.

## What does work

Send the verbs to the codec at runtime with **`alc-verb`**, the utility that ships in the
[AppleALC source tree](https://github.com/acidanthera/AppleALC/tree/master/alc-verb).

**1. Enable verb support.** Add `alcverbs=1` to your boot arguments.

**2. Build `alc-verb`** (needs Command Line Tools):

```bash
mkdir -p /tmp/av && cd /tmp/av
curl -sLO https://raw.githubusercontent.com/acidanthera/AppleALC/master/alc-verb/main.c
curl -sLO https://raw.githubusercontent.com/acidanthera/AppleALC/master/alc-verb/hdaverb.h
curl -sLO https://raw.githubusercontent.com/acidanthera/AppleALC/master/AppleALC/UserKernelShared.h
clang -O2 -framework IOKit -framework CoreFoundation main.c -o alc-verb
sudo cp alc-verb /usr/local/bin/
```

**3. The verbs themselves:**

```bash
alc-verb 0x17 0x71c 0x30     # pin config byte 0  ┐
alc-verb 0x17 0x71d 0x01     # pin config byte 1  ├─ 0x90170130 = internal speaker
alc-verb 0x17 0x71e 0x17     # pin config byte 2  │
alc-verb 0x17 0x71f 0x90     # pin config byte 3  ┘
alc-verb 0x17 0x701 0x01     # connection select → DAC 0x03
alc-verb 0x17 0x707 0x40     # pin widget control: output enable
alc-verb 0x17 0x300 0xb000   # output amp, both channels, unmute
```

**4. Make it permanent** with [`scripts/woofer.sh`](../scripts/woofer.sh) and
[`scripts/com.local.woofer.plist`](../scripts/com.local.woofer.plist):

```bash
sudo cp scripts/woofer.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/woofer.sh
sudo cp scripts/com.local.woofer.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.woofer.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.woofer.plist
```

The daemon waits for audio to come up, applies the verbs, and re-applies them if the codec is reset —
which happens on wake and when the output device changes.

## Why DAC 0x03, and why a daemon

Node `0x17` can be fed from DAC `0x02`, `0x03` or `0x06`. `0x02` is the one the tweeters use.

Both `0x02` and `0x03` carry the same audio stream, **and macOS moves both of them together when you change
the system volume** — verified:

```
volume 30%:  0x02 = 0x30   0x03 = 0x30
volume 90%:  0x02 = 0x53   0x03 = 0x53
```

Putting the woofers on `0x03` means their level can be held *above* the tweeters' by a fixed amount, giving
a genuine hardware bass lift that still tracks the volume slider. A one-off gain change would simply be
overwritten the next time you touch the volume — hence the daemon, which maintains

```
gain(0x03) = min( gain(0x02) + OFFSET, CAP )
```

Both are at the top of `woofer.sh`. Defaults: `OFFSET=13` (13 × 0.75 dB ≈ +10 dB) and `CAP=0x52`.

The pin amps on this codec are **mute-only** (`AMP-OUT cap = 0x80000000`), so all gain lives on the DACs —
do not waste time trying to set a level on `0x17` itself. The DAC amps have 87 steps of 0.75 dB, maximum
`0x57`.

## Measurements

Measured with the internal microphone (`tools/rec.swift` to record, `tools/measure-thd.py` to analyse),
input gain pinned so the levels are comparable between runs.

**Before and after, at 200 Hz:**

| | Level |
|---|---|
| Tweeters only (stock) | **−108.0 dB** |
| Woofers enabled, gain `0x4e` | **−54.7 dB** |

That is a 53 dB difference. The tweeters produce essentially nothing below about 200 Hz — the "no bass"
complaint is literally accurate, not a matter of taste.

**Distortion versus gain, woofers at 200 Hz:**

| DAC gain | Level | THD |
|---|---|---|
| `0x41` | −67.0 dB | 0.7 % |
| `0x48` | −62.1 dB | 1.8 % |
| `0x4e` | −54.6 dB | 0.7 % |
| `0x52` | −52.6 dB | 2.6 % |
| `0x57` (max) | −51.6 dB | **13.8 %** |

Above `0x52` there is audible buzz, confirmed by ear as well as by measurement. `CAP=0x52` is the default
for that reason; lower it to `0x4e` if you want to be conservative.

**A control, because the microphone is a suspect too.** Small internal microphones can rattle at high sound
pressure, which would fake distortion. Driving the *tweeters* to the same measured levels at 1 kHz:

| Level | Tweeters @1 kHz | Woofers @200 Hz |
|---|---|---|
| ≈ −54 dB | 32 % THD | 2.6 % THD |

If the microphone were the bottleneck, both would look the same at equal sound pressure. They differ by a
factor of twelve, so the distortion being measured is in the drivers, not in the recording chain. (Note in
passing what this says about the tweeters: 47 % THD at full gain. They are not good speakers.)

## Caveats

- The woofers are small. This gives you real low-mid content around 100–250 Hz; it does not give you deep
  bass. Nothing was measurable at 70 Hz from either driver — though the internal microphone may not reach
  that low either, so treat that as inconclusive rather than proven absent.
- `alcverbs=1` must stay in boot-args or the daemon silently does nothing.
- The daemon polls every 3 seconds. That is cheap, but it does mean a brief lag after a volume change.

## Recording tools

`tools/rec.swift` records from the default input to a WAV; `tools/measure-thd.py` reports the level of a
fundamental plus its second and third harmonics.

```bash
swiftc -O tools/rec.swift -o ~/tools/rec
~/tools/rec /tmp/r.wav 4
python3 tools/measure-thd.py /tmp/r.wav 200
```

One practical note: **a process started over SSH cannot use the microphone.** macOS denies it silently and
hands you a file full of zeros rather than prompting. Launch the measurement from a GUI session instead —
`open -a Terminal /path/to/script.command` works and triggers the permission prompt properly.
