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

**Switching to another AppleALC layout is not the answer either** — though for a subtler reason than it first
appears. `Resources/ALC289/` in the AppleALC repository holds only DSP graph definitions (`layoutNN.xml`,
`PlatformsNN.xml`), which is what led to an early conclusion here that AppleALC carries no pin data for this
codec at all. That was wrong: the pin configurations live in `Resources/PinConfigs.kext/Contents/Info.plist`
and end up in the built kext's own `Info.plist`. Layout 13 has an entry there — it just omits node `0x17`.
Layout 93 does set it, so switching to 93 *would* make the woofers play, at the cost of its own path map
(both pairs on DAC `0x02`, no separate level control) and its different microphone pins.

## What does work

Two things are needed, and they are separate:

**A. Make the pin configuration correct at boot** — this is what actually turns the woofers on, and it needs
no daemon and no compiling.

**B. Hold the woofers louder than the tweeters** — optional, for a bass lift; this does need a small daemon.

### A. The pin config, permanently

AppleALC reads its pin configurations from `HDAConfigDefault` in **its own bundle's `Info.plist`** — a plain
file, not something compiled into the binary. So it can simply be edited.

In `EFI/OC/Kexts/AppleALC.kext/Contents/Info.plist`, under
`IOKitPersonalities → as.vit9696.AppleALC → HDAConfigDefault`, find the entry with `CodecID = 283902601`
(`0x10EC0289`) and `LayoutID = 13`, and append four verbs to its `ConfigData`:

```
01771c11 01771d01 01771e17 01771f90     →  pin 0x17 = 0x90170111
```

Association 1, sequence 1 — the same group as node `0x14` (`0x90170110`), which keeps its firmware value.

That is the whole fix. Reboot and the woofers play, with nothing running in userspace.

> This omission is upstream, not local: AppleALC's layout-13 entry is *named* "XPS 15 9500 4 Speakers" but
> never sets node `0x17`. Submitted as
> [acidanthera/AppleALC#965](https://github.com/acidanthera/AppleALC/pull/965) — once merged, this manual edit
> becomes unnecessary. `layout-id 93` (XPS 9500 4K) already sets the pin, which is why that layout drives all
> four speakers today.

Verbs for pin-widget enable (`0x707`) and connection select (`0x701`) were tried too and are **not** needed:
AppleHDA does both itself once the pin is declared. They also do not stick — reading `0xf07` after boot
returns `0` even while the woofers are audibly playing, because the pin is enabled only for the duration of
a stream.

### B. The bass lift, with a daemon

Optional. See [`scripts/woofer.sh`](../scripts/woofer.sh) and
[`scripts/com.local.woofer.plist`](../scripts/com.local.woofer.plist):

```bash
sudo cp scripts/woofer.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/woofer.sh
sudo cp scripts/com.local.woofer.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.woofer.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.woofer.plist
```

It needs `alc-verb`, which is in the [AppleALC source tree](https://github.com/acidanthera/AppleALC/tree/master/alc-verb)
and needs `alcverbs=1` in boot-args:

```bash
mkdir -p /tmp/av && cd /tmp/av
curl -sLO https://raw.githubusercontent.com/acidanthera/AppleALC/master/alc-verb/main.c
curl -sLO https://raw.githubusercontent.com/acidanthera/AppleALC/master/alc-verb/hdaverb.h
curl -sLO https://raw.githubusercontent.com/acidanthera/AppleALC/master/AppleALC/UserKernelShared.h
clang -O2 -framework IOKit -framework CoreFoundation main.c -o alc-verb
sudo cp alc-verb /usr/local/bin/
```

(`UserKernelShared.h` lives outside the `alc-verb` directory and is easy to miss.)

## A real crossover is not reachable

Worth stating so nobody spends time on it. Feeding the woofers only low frequencies and the tweeters only
high would be the right way to make this machine sound good — and it cannot be done here.

Layout 13's path map already looks promising:

```
0x14 → DAC 0x02 [ch1, ch2]
0x17 → DAC 0x03 [ch5, ch6]      ← a separate channel pair
```

But **AppleHDA keeps the built-in output at two channels regardless.** With the pin declared and the path
routed, `kAudioStreamPropertyAvailableVirtualFormats` still offers `2ch` only, and the `ch5/ch6` path is
never activated. Tested with two different pin associations — matching `0x14`'s group (assoc 1, seq 1) and a
separate one (assoc 6, as layout 93 uses) — no difference.

AppleHDA also cannot be made to re-enumerate without a reboot: `kmutil unload -b com.apple.driver.AppleHDA`
fails with `unsupported function`, and restarting `coreaudiod` does not rebuild the device.

What is left in theory is a custom `Platforms` XML declaring a genuine multichannel device, which does need
an AppleALC rebuild and therefore Xcode — plus crossover DSP software, which macOS does not provide. Neither
step is proven to work. The practical alternative is a system-wide EQ, shaped from the measured curves.

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
gain(0x03) = min( system, CAP )
gain(0x02) = max( gain(0x03) − SPREAD, FLOOR )
```

All three are at the top of `woofer.sh`. See [One knob, not two](#one-knob-not-two) for why it ended up
as a single parameter.

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

## A hardware tone control

macOS has no built-in EQ, but this machine has something almost as useful: **two independent DAC gains
feeding two driver pairs with very different responses.**

| | Node 0x14 → DAC 0x02 | Node 0x17 → DAC 0x03 |
|---|---|---|
| below 200 Hz | nothing | works from ~120 Hz |
| 500 Hz | −42 dB | **−20 dB** |
| 2 kHz | **−16.5 dB** | −23 dB |
| 4 kHz | −36 dB | −28 dB |

The upper pair carries the 2 kHz peak — the harshness — and produces nothing at the bottom. The lower pair
covers 120 Hz to 1 kHz. So *changing their relative level is a tone control*, and it needs no software at all.

[`scripts/woofer.sh`](../scripts/woofer.sh) maintains it:

```
gain(0x03) = min( system, CAP )                    # lower pair
gain(0x02) = max( gain(0x03) − SPREAD, FLOOR )     # upper pair
```

Defaults: `SPREAD=0` (neutral — see below), `CAP=0x52`, `FLOOR=0x20`.

**Why `CAP=0x48`.** At 200 Hz the woofers saturate exactly there — measured, every value above it is identical
within error. Pushing higher gains nothing at the bottom and only inflates 300 Hz–1 kHz, which is the boxy
region. So the cap limits the *boost* and never attenuates: at high system volume the lower pair simply tracks
the slider, because the driver is already at its limit.

**Why `SPREAD` is modest.** Trimming the upper pair hits the 2 kHz peak precisely — 12 steps drops 2 kHz by
4.6 dB while 500 Hz falls only 1.1 dB, because 500 Hz comes from the *other* pair. But it also takes 4 kHz
down with it: at 12 steps the top end lost 6.7 dB and the result was noticeably dull. Eight steps was settled on by ear — four was barely audible, twelve was
dull. Measurement had reached its limit by then: a single microphone position cannot resolve the last few
decibels, so the final value is a listening judgement, not a measured one.

What this cannot do is the high-pass below 110 Hz or the shelf above 4.5 kHz — those still need a real EQ.
Two of the five targets above are covered in hardware; the rest is software if you want it.

### Tuning it by ear

Three numbers at the top of `scripts/woofer.sh`, and the honest position is that measurement has taken this
as far as it usefully can — a single microphone position cannot resolve the last few decibels, and absolute
levels are not comparable between sessions. From here it is taste.

| Change | Effect |
|---|---|
| `SPREAD` up | more bass and less harshness at 2 kHz, but also less air at 4 kHz. Past ~12 steps it sounds dull |
| `CAP` down | protects the woofers at high volume; also lowers overall loudness there |

After editing:

```bash
sudo cp scripts/woofer.sh /usr/local/bin/
sudo launchctl kickstart -k system/com.local.woofer
```

Changes take about 30 seconds to apply, and only after the volume slider moves — the daemon acts on the
moment macOS sets both DACs to the same value.

### The honest outcome: neutral

`SPREAD` defaults to **0**, and that is a result, not laziness.

Eight steps (−6 dB on the upper pair) sounds good on hip-hop, where the energy sits low. On dense rock it does
not: tested on Linkin Park's *Numb*, it produced audible holes in the sound. The midrange and treble from
2–8 kHz come from the upper pair, and any trim eats into them. At zero it sounds right.

The reason is the one thing that cannot be fixed here: **both pairs receive the full-range signal, with no
crossover.** Trading level between them is a compromise, not a fix. Boost the woofers and the 300 Hz–1 kHz
region inflates; trim the tweeters and the upper midrange thins out. There is no setting that is right for all
material, which is exactly what a crossover would have solved.

So the daemon ships neutral. With `SPREAD=0` its only remaining job is restoring node `0x17`'s pin
configuration if the codec resets it — a safety net, since the boot-time `ConfigData` already sets it.

If you do want more bass: 2–4 steps is tolerable, 8 is audible on rock, 12 costs 6.7 dB at 4 kHz (measured).
It is a taste knob, and the measurements above tell you what each step costs.

### One knob, not two

An earlier version had two: a boost for the lower pair and a trim for the upper. They stack, and the
result depended on volume in a way that sounded wrong — at 40 % the spread reached 18 dB and the bass
boomed, while at 85 % the boost hit its ceiling and never applied, leaving a well-balanced 6 dB. The
machine sounded better loud than quiet, which is the wrong way round for a tone control.

So there is one parameter now, `SPREAD`, and it holds the same distance between the pairs at every volume:

```
gain(0x03) = min(system, CAP)          # lower pair, never boosted above the slider
gain(0x02) = max(gain(0x03) − SPREAD, FLOOR)
```

The upper pair is tied to the *lower* one rather than to the slider. Otherwise at 100 % the lower pair hits
`CAP` while the upper keeps rising, and the spread collapses from 6 dB to 2 dB — the tone would change at
maximum volume. Verified: +6.0 dB at 25, 40, 55, 70, 85 and 100 %.

### Reading DAC gains is not always reliable

`alc-verb 0x02 0xb 0x8000` occasionally returns `0x00000000` while audio is plainly playing at slider level.
The daemon therefore only acts when **both** DACs read the same value — which is the signature of macOS having
just set them from the volume slider — and refuses to act on anything below `FLOOR`.

An earlier version computed the "system volume" from those same registers that it was itself writing. That is
circular, and on the first bad read it drove both gains to zero and silenced the machine. If you adapt this
script, keep that guard.

## Equalisation: what to aim for

A crossover is out of reach, so a system-wide EQ is what actually improves the sound. These are not
guessed settings — they follow from the measured response.

Combined response of both driver pairs at equal gain, relative to the 500 Hz–1 kHz average:

| Hz | relative |
|---|---|
| 120 | **−31 dB** |
| 160 | −21 dB |
| 200 | −10 dB |
| 300 | −2 dB |
| 500 | +2 dB |
| 800 | −1 dB |
| 1000 | −0.5 dB |
| 2000 | **+5 dB** |
| 4000 | −6 dB |

Below 120 Hz there is nothing at all, there is a broad plateau from 300 Hz to 1 kHz, a pronounced peak at
2 kHz, and a drop above it.

**The target:**

| What | Where | How much | Why |
|---|---|---|---|
| High-pass | 110 Hz, steep (24 dB/oct) | — | Nothing below it but cone excursion and distortion. Removing it lets the drivers play louder cleanly — the single biggest gain here. |
| Boost | 170 Hz, Q 1.0 | **+7 dB** | The lowest range the woofers still respond in. |
| Cut | 500 Hz, Q 1.0 | **−3 dB** | The woofers' own peak; the source of boxiness. |
| Cut | 2 kHz, Q 1.2 | **−5 dB** | The tweeters' peak; the source of harshness. |
| High shelf | above 4.5 kHz | **+4 dB** | Restores the top end, which rolls off. |

macOS has no built-in system EQ, so this needs third-party software — [eqMac](https://eqmac.app) is the usual
free choice; SoundSource is the paid one. Both install a virtual audio device, which becomes the default
output; worth doing when you are not about to need working sound.

Treat these as a starting point and adjust by ear. The measurement is from a single microphone position
10 cm away, so the fine structure — the exact height of the 2 kHz peak, the dip at 4 kHz — is partly room
and cabinet reflection rather than pure driver response. The broad shape is reliable; individual decibels
are not.

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
