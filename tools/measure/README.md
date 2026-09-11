# Measuring laptop speakers without a measurement microphone

These four scripts are what produced the numbers in [woofers.md](../../docs/woofers.md). Pure Python, no
numpy — a Goertzel filter is five lines and runs fast enough on a 40-second recording.

| | |
|---|---|
| `gen-steps.py` | writes the test signal: a 1 kHz marker, then 25 third-octave tones, 34.5 s total |
| `analyze-steps.py` | one recording → level and THD per frequency |
| `average.py` | several recordings from different mic positions → spatially averaged response |
| `compare.py` | two recordings → what the EQ actually did, against what it was designed to do |

## How a measurement run works

```bash
python gen-steps.py steps.wav
scp steps.wav mac:~/                       # the laptop under test plays it

# start the recorder first, the playback second
ssh mac 'sleep 2; afplay ~/steps.wav' &
ffmpeg -f dshow -i audio="<your mic>" -sample_rate 44100 -t 40 -y run.wav

python analyze-steps.py run.wav
```

The signal starts with a 1 kHz marker so the analyser can align itself; everything after that is on a fixed
schedule, so each tone is read at a known time rather than by hunting for energy peaks.

## Four things that will bite you

**1. The marker is the same frequency as one of the test tones.** An analyser that finds the marker by
looking for the strongest 1 kHz burst will happily latch onto the 1 kHz *tone*, 17 seconds later, and every
reading after that is garbage. `find_marker_by_tone` builds a 1 kHz envelope and takes the *first* sustained
plateau, not the loudest one.

**2. Take the onset, not the centre of the best window.** With a 0.6 s analysis window inside a 1.0 s tone
the slack is ±0.2 s. A detector that returns the middle of its search window is half a window late, which is
already out of tolerance.

**3. Playback does not always start when you tell it to.** One run here started nine seconds late. Always
print where the marker was found and how far it stands above the noise; if that margin is small, throw the
run away.

**4. Keep the drive level identical between runs you intend to compare.** On this machine a daemon was
setting the codec's DAC gain from its own previous value, so the level depended on the volume history —
5.25 dB between two runs that looked identical in the UI. Normalisation hides a constant offset, but not the
driver compression it causes.

## What this rig can and cannot tell you

Measured with a Logitech C930e webcam at ~10 cm. Two consecutive runs with nothing touched:

| Band | Repeatability |
|---|---|
| 160 Hz – 2.5 kHz | **±1.5 dB** |
| above 3 kHz | 4–7 dB |

So the trustworthy band is 160 Hz to 2.5 kHz. Above that, two things conspire: the webcam applies AGC and
noise suppression that cannot be turned off through ffmpeg, and at 10 kHz the wavelength is 3.4 cm, so
moving the microphone two centimetres rebuilds the entire interference pattern.

**Spatial averaging is what makes the numbers mean something.** A single position showed a 12 dB notch at
630 Hz; from another position it was 4 dB. `average.py` combines several positions by power and prints the
spread per frequency — and that spread column is the useful one:

- large spread (10–13 dB) — interference. Do not equalise it; it moves when your head moves.
- small spread (3 dB) — a real property of the system. On this machine the 630 Hz dip has the *smallest*
  spread in the whole table, which is what identified it as a crossover artefact rather than a room effect.

Three positions was the minimum that separated those two cases. Six to eight would be better, and costs
nothing but time.

## Verifying an EQ rather than guessing

`compare.py` takes a recording with the EQ engaged and one without, from the same microphone position, and
subtracts them. The microphone's own response cancels out, and so does most of the comb filtering. It then
computes what the designed filters *should* have produced — RBJ cookbook biquads, same maths the driver
uses — and prints the error.

That is how the speaker EQ was confirmed: **average error 0.7 dB, worst 2.2 dB**, against a rig that repeats
to ±1.5 dB. Without that step, "it sounds better" would have stayed an opinion.

Normalise both the measurement and the designed curve over the same reference band, and pick a band the EQ
does not touch — here 800–1250 Hz. Normalising over 500 Hz, which the curve was cutting, hid the error that
mattered.
