"""Generator stupenchatogo tonalnogo signala dlya izmereniya AChH dinamikov.

Odna zapis - vsya harakteristika. Struktura:
  0.5 s tishiny  (zamer shumovogo poroga)
  1.0 s marker 1 kHz  (po nemu analizator vyravnivaetsya)
  0.5 s tishiny
  dalee dlya kazhdoy chastoty: 1.0 s ton + 0.3 s tishiny

Amplituda -12 dBFS: zapas do klippinga i ne peregruzhaet nizkochastotniki.
"""
import math, struct, sys, wave

SR = 48000
AMP_DB = -12.0
MARKER_HZ = 1000.0
LEAD_S = 0.5
MARKER_S = 1.0
AFTER_MARKER_S = 0.5
TONE_S = 1.0
GAP_S = 0.3

# Tretoktavnyy ryad. Nizhe 63 Gts dinamiki ne igrayut voobshche - proveryali.
FREQS = [63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000,
         1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000]


def tone(freq, seconds, amp):
    n = int(SR * seconds)
    out = []
    # Plavnye fronty 20 ms, chtoby ne bylo shchelchkov i razmazyvaniya spektra.
    ramp = int(SR * 0.02)
    for i in range(n):
        v = amp * math.sin(2.0 * math.pi * freq * i / SR)
        if i < ramp:
            v *= i / ramp
        elif i > n - ramp:
            v *= (n - i) / ramp
        out.append(v)
    return out


def silence(seconds):
    return [0.0] * int(SR * seconds)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "steps.wav"
    amp = 10 ** (AMP_DB / 20.0)

    samples = []
    samples += silence(LEAD_S)
    samples += tone(MARKER_HZ, MARKER_S, amp)
    samples += silence(AFTER_MARKER_S)
    for f in FREQS:
        samples += tone(float(f), TONE_S, amp)
        samples += silence(GAP_S)

    data = struct.pack("<%dh" % len(samples),
                       *[max(-32767, min(32767, int(x * 32767))) for x in samples])
    w = wave.open(path, "w")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data)
    w.close()

    dur = len(samples) / SR
    print("  fayl:      %s" % path)
    print("  dlitelnost: %.1f s" % dur)
    print("  chastot:    %d (ot %d do %d Gts)" % (len(FREQS), FREQS[0], FREQS[-1]))
    print("  uroven:     %.0f dBFS" % AMP_DB)


if __name__ == "__main__":
    main()
