"""Prostranstvennoe usrednenie neskolkih zapisey s raznyh pozicii mikrofona.

Odna tochka mikrofona daet grebenchatuyu interferenciyu: provaly do 12 dB, kotorye
"pereezzhayut" pri sdvige na santimetry. Usrednenie po moshchnosti neskolkih pozicii
razmazyvaet interferenciyu i ostavlyaet nastoyashchuyu harakteristiku dinamikov.

Zapusk:  python average.py zapis1.wav zapis2.wav zapis3.wav ...
"""
import math, struct, sys, wave

MARKER_S, AFTER_MARKER_S, TONE_S, GAP_S, ANALYZE_S = 1.0, 0.5, 1.0, 0.3, 0.6
FREQS = [63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000,
         1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000]
REF_BAND = (800, 1250)
TRUST_BAND = (160, 2500)


def goertzel(s, sr, f):
    n = len(s)
    k = int(0.5 + n * f / sr)
    w = 2.0 * math.pi * k / n
    c = 2.0 * math.cos(w)
    s1 = s2 = 0.0
    for x in s:
        s0 = x + c * s1 - s2
        s2, s1 = s1, s0
    return math.sqrt(max(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) / (n / 2.0)


def db(m):
    return 20.0 * math.log10(m) if m > 1e-12 else -200.0


def rms(seg):
    return math.sqrt(sum(x * x for x in seg) / len(seg)) if seg else 0.0

def find_marker_by_tone(s, sr, search_s=25.0):
    """Nahodit FRONT markera 1 kHz s tochnostyu do 10 ms.

    Dva podvoha, na kotoryh detektor lomalsya:
      1) v samoy posledovatelnosti est ton 1 kHz - poisk maksimuma cheplyalsya
         za nego, i razmetka uezzhala na 17 sekund;
      2) brat centr okna nelzya - poluchaetsya sdvig na polokna, a dopusk u nas
         vsego +-0.2 s pri okne analiza 0.6 s vnutri tona 1.0 s.
    Poetomu stroim ogibayushchuyu 1 kHz i ishchem imenno nachalo pervoy
    ustoychivoy polki.
    """
    win = int(sr * 0.10)
    hop = int(sr * 0.01)
    limit = min(len(s) - win, int(sr * search_s))
    env = [(i, goertzel(s[i:i + win], sr, MARKER_HZ)) for i in range(0, limit, hop)]
    if not env:
        return 0, 0.0
    peak = max(v for _, v in env)
    thr = 0.3 * peak
    need = 30                      # 300 ms podryad - eto uzhe polka, a ne vsplesk
    run = 0
    for idx, (i, v) in enumerate(env):
        if v >= thr:
            run += 1
            if run >= need:
                return env[idx - run + 1][0], peak
        else:
            run = 0
    return env[0][0], peak


def measure(path):
    w = wave.open(path, "r")
    n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
    raw = w.readframes(n)
    w.close()
    v = struct.unpack("<%dh" % (len(raw) // 2), raw)
    if ch > 1:
        v = v[0::ch]
    s = [x / 32768.0 for x in v]

    floor = rms(s[:int(sr * 0.3)]) or 1e-6
    m0, _ = find_marker_by_tone(s, sr)

    base = m0 + int(sr * (MARKER_S + AFTER_MARKER_S))
    skip = (TONE_S - ANALYZE_S) / 2.0
    mags, thds = {}, {}
    for i, f in enumerate(FREQS):
        t0 = base + int(sr * (i * (TONE_S + GAP_S) + skip))
        t1 = t0 + int(sr * ANALYZE_S)
        if t1 > len(s):
            mags[f], thds[f] = None, None
            continue
        seg = s[t0:t1]
        m1 = goertzel(seg, sr, float(f))
        h2 = goertzel(seg, sr, float(f) * 2)
        h3 = goertzel(seg, sr, float(f) * 3)
        mags[f] = m1
        thds[f] = 100.0 * math.sqrt(h2 * h2 + h3 * h3) / m1 if m1 > 1e-9 else None
    return mags, thds, floor


def main():
    paths = sys.argv[1:]
    if len(paths) < 2:
        sys.exit("  nuzhny hotya by dve zapisi")

    per = [measure(p) for p in paths]
    floors = [f for (_, _, f) in per]

    print("  usredneno zapisey: %d" % len(paths))
    for p, (_, _, fl) in zip(paths, per):
        print("    %-22s shum %.1f dB" % (p, db(fl)))
    print("  usrednenie po moshchnosti; normirovka %d-%d Gts" % REF_BAND)
    print()

    avg = {}
    spread = {}
    for f in FREQS:
        vals = [m[f] for (m, _, _) in per if m[f] is not None]
        if not vals:
            continue
        p = sum(v * v for v in vals) / len(vals)
        avg[f] = math.sqrt(p)
        dbs = [db(v) for v in vals]
        spread[f] = max(dbs) - min(dbs)

    ref = [db(avg[f]) for f in avg if REF_BAND[0] <= f <= REF_BAND[1]]
    base = sum(ref) / len(ref)

    print("  %-7s %9s %9s %8s   %s" % ("Gts", "otn. dB", "razbros", "THD %", "profil"))
    print("  " + "-" * 64)
    for f in FREQS:
        if f not in avg:
            continue
        rel = db(avg[f]) - base
        thds = [t[f] for (_, t, _) in per if t[f] is not None]
        thd = sum(thds) / len(thds) if thds else 0.0
        weak = db(avg[f]) - db(max(floors)) < 10
        note = "  <- shum" if weak else ("" if TRUST_BAND[0] <= f <= TRUST_BAND[1] else "  <- vne polosy")
        pos = int(round(max(-20.0, min(20.0, rel))))
        bar = list(" " * 41)
        bar[20] = "|"
        bar[20 + pos] = "#"
        print("  %-7d %9.1f %9.1f %8.1f   %s%s" % (f, rel, spread[f], thd, "".join(bar), note))
    print("  " + "-" * 64)
    print("  Razbros = raznica mezhdu pozitsiyami. Bolshoy razbros = interferenciya,")
    print("  takuyu tochku ekvalayzerom pravit nelzya - ona pereedet pri sdvige golovy.")


if __name__ == "__main__":
    main()
