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

Both are at the top of `woofer.sh`. Defaults: `OFFSET=16` (16 × 0.75 dB ≈ +12 dB) and `CAP=0x52`.

The pin amps on this codec are **mute-only** (`AMP-OUT cap = 0x80000000`), so all gain lives on the DACs —
do not waste time trying to set a level on `0x17` itself. The DAC amps have 87 steps of 0.75 dB, maximum
`0x57`.

## Measurements

Measured with an **external microphone** — a Logitech C930e on a stand 10 cm from the laptop, recorded on a
separate machine with ffmpeg, analysed with a Goertzel filter at the tone frequency. Room noise floor during
the run: −98.4 dB RMS.

> **An earlier version of this document had different numbers, taken with the laptop's own microphone. Those
> were wrong and have been replaced.** An internal microphone sits in the chassis and picks up structure-borne
> vibration, so readings depend heavily on what the laptop is standing on — and it invented distortion that
> is not there. Do not characterise these speakers with the built-in mic.

**Tweeters alone:**

| Tone | Level | THD |
|---|---|---|
| 1 kHz | **−40.4 dB** | 0.6 % |
| 200 Hz | **−127.5 dB** | — (below the noise floor) |

The tweeters produce *nothing* at 200 Hz — 87 dB below their own 1 kHz output, and below the room noise. The
"no bass" complaint is literal. At 1 kHz they are clean: 0.6 % THD.

**Woofers alone, 200 Hz, sweeping the DAC gain:**

| DAC gain | Level | THD |
|---|---|---|
| `0x41` | −42.8 dB | 1.1 % |
| `0x48` | **−29.4 dB** | 2.4 % |
| `0x4e` | −29.3 dB | 2.7 % |
| `0x52` | −29.0 dB | 2.6 % |
| `0x55` | −29.5 dB | 2.7 % |
| `0x57` (max) | −29.3 dB | 2.8 % |

Two things fall out of this. Against the tweeters' −127.5 dB, the woofers give −29 dB at the same
frequency — about **98 dB more output at 200 Hz**. And the level **saturates at `0x48`**: everything above it
is identical within measurement error, so gain past that point buys nothing here.

**Woofers alone, 120 Hz:**

| DAC gain | Level | THD |
|---|---|---|
| `0x4e` | −45.3 dB | 14.2 % |
| `0x52` | −43.6 dB | 9.2 % |
| `0x55` | −42.5 dB | 12.2 % |
| `0x57` (max) | −39.9 dB | **57.2 %** |

Lower down there is still headroom in level, but also a cliff: at the codec maximum the third harmonic reaches
−44.7 dB and THD hits 57 %. That is the driver bottoming out, and it is audible as a buzz.

`CAP=0x52` follows from these two tables — at 200 Hz the output is already saturated by then, and at 120 Hz it
is the least distorted of the measured points.

## Caveats

- The woofers are small. This gives real low-mid content around 120–250 Hz; it is not deep bass. Nothing was
  measurable at 70 Hz.
- `alcverbs=1` must stay in boot-args or the daemon silently does nothing.
- The daemon polls every 3 seconds. That is cheap, but it does mean a brief lag after a volume change.
- Sending gain verbs by hand can leave macOS's idea of the volume out of step with the codec — the slider
  reads 85 % while the DAC sits at zero. Nudging the volume resyncs it. This only happens after manual
  experimentation, not in normal use.

## Recording tools

`tools/rec.swift` records from the default input to a WAV; `tools/measure-thd.py` reports the level of a
fundamental plus its second and third harmonics.

**Prefer an external microphone on a second machine.** The internal one is not a usable instrument here, for
the reasons above. The setup that produced the numbers in this document was: tone files on the Mac played with
`afplay` over SSH, recorded on a Windows box with

```
ffmpeg -f dshow -i audio="Microphone (...)" -t 5 -ac 1 -ar 48000 -y out.wav
```

and analysed with `tools/measure-thd.py`. Keep the laptop and the microphone still between runs, or absolute
levels are not comparable.

If you do use the built-in microphone: **a process started over SSH cannot reach it.** macOS denies access
silently and hands you a file full of zeros rather than prompting. Launch from a GUI session instead —
`open -a Terminal /path/to/script.command` triggers the permission prompt properly.
