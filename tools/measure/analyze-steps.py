"""Analiz zapisi stupenchatogo signala: uroven i iskazheniya na kazhdoy chastote.

Vyravnivanie po markeru 1 kHz v nachale, dalshe raspisanie izvestno, poetomu
kazhdyy ton beretsya po svoemu vremeni, a ne poiskom maksimuma energii.

Zapusk:  python analyze-steps.py zapis.wav [metka]
"""
import math, struct, sys, wave

SR_EXPECT = 48000
MARKER_HZ = 1000.0
LEAD_S = 0.5
MARKER_S = 1.0
AFTER_MARKER_S = 0.5
TONE_S = 1.0
GAP_S = 0.3
ANALYZE_S = 0.6          # srednyaya chast tona, bez frontov

FREQS = [63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000,
         1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000]

# Otnositelno chego normiruem krivuyu - srednee po seredine diapazona.
REF_BAND = (500, 1000)


def goertzel(s, sr, f):
    n = len(s)
    k = int(0.5 + n * f / sr)
    w = 2.0 * math.pi * k / n
    c = 2.0 * math.cos(w)
    s1 = s2 = 0.0
    for x in s:
        s0 = x + c * s1 - s2
        s2 = s1
        s1 = s0
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


def load(path):
    w = wave.open(path, "r")
    n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
    raw = w.readframes(n)
    w.close()
    if sw != 2:
        sys.exit("  podderzhivaetsya tolko 16 bit, a tut %d" % (sw * 8))
    v = struct.unpack("<%dh" % (len(raw) // 2), raw)
    if ch > 1:
        v = v[0::ch]
    return [x / 32768.0 for x in v], sr


def main():
    path = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else ""
    s, sr = load(path)
    if sr != SR_EXPECT:
        print("  vnimanie: chastota diskretizacii %d, a ozhidalas %d" % (sr, SR_EXPECT))

    floor = rms(s[:int(sr * 0.3)]) or 1e-6
    m0, _ = find_marker_by_tone(s, sr)

    print("  fayl: %s %s" % (path, ("(" + label + ")") if label else ""))
    print("  dlitelnost zapisi: %.1f s | shumovoy porog: %.1f dB | marker v %.2f s"
          % (len(s) / sr, db(floor), m0 / sr))
    print()

    # Proverim sam marker - esli on tihiy, ves zamer somnitelen.
    mseg = s[m0 + int(sr * 0.2): m0 + int(sr * 0.8)]
    mlev = db(goertzel(mseg, sr, MARKER_HZ))
    print("  marker 1 kHz: %.1f dB (zapas nad shumom %.1f dB)" % (mlev, mlev - db(floor)))
    print()

    base = m0 + int(sr * (MARKER_S + AFTER_MARKER_S))
    skip = (TONE_S - ANALYZE_S) / 2.0

    rows = []
    for i, f in enumerate(FREQS):
        t0 = base + int(sr * (i * (TONE_S + GAP_S) + skip))
        t1 = t0 + int(sr * ANALYZE_S)
        if t1 > len(s):
            rows.append((f, None, None))
            continue
        seg = s[t0:t1]
        m1 = goertzel(seg, sr, float(f))
        h2 = goertzel(seg, sr, float(f) * 2)
        h3 = goertzel(seg, sr, float(f) * 3)
        thd = 100.0 * math.sqrt(h2 * h2 + h3 * h3) / m1 if m1 > 1e-9 else 0.0
        rows.append((f, db(m1), thd))

    ref = [lv for (f, lv, _) in rows if lv is not None and REF_BAND[0] <= f <= REF_BAND[1]]
    ref_db = sum(ref) / len(ref) if ref else 0.0

    print("  %-8s %10s %10s %8s   %s" % ("Gts", "uroven dB", "otn. dB", "THD %", "profil"))
    print("  " + "-" * 62)
    for f, lv, thd in rows:
        if lv is None:
            print("  %-8d %10s" % (f, "net dannyh"))
            continue
        rel = lv - ref_db
        nf = db(floor)
        mark = "" if lv - nf > 10 else "  <- na urovne shuma"
        bar_pos = int(round(max(-20.0, min(20.0, rel))))
        bar = list(" " * 41)
        bar[20] = "|"
        bar[20 + bar_pos] = "#"
        print("  %-8d %10.1f %10.1f %8.1f   %s%s" % (f, lv, rel, thd, "".join(bar), mark))
    print("  " + "-" * 62)
    print("  opora (%d-%d Gts): %.1f dB" % (REF_BAND[0], REF_BAND[1], ref_db))


if __name__ == "__main__":
    main()
