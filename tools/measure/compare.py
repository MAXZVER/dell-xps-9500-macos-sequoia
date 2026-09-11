"""Sravnenie dvuh zapisey: chto ekvalayzer sdelal na dele protiv togo, chto zadumano.

Zapusk:  python compare.py zapis-s-eq.wav zapis-bez-eq.wav

Normirovka po polose 800-1250 Gts: tam u nashey krivoy net ni odnoy polosy,
blizhayshie (500 i 2000) dalshe chem na oktavu. Normirovat po 500 Gts nelzya -
imenno ego ekvalayzer i rezhet.
"""
import math, struct, sys, wave

MARKER_HZ = 1000.0
LEAD_S, MARKER_S, AFTER_MARKER_S, TONE_S, GAP_S, ANALYZE_S = 0.5, 1.0, 0.5, 1.0, 0.3, 0.6
FREQS = [63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000,
         1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000]
REF_BAND = (800, 1250)
TRUST_BAND = (160, 2500)     # gde stend povtoryaem v predelah ~1.5 dB

# Nasha krivaya v layout13.xml. tip: hp / lp / peak
EQ_BANDS = [
    ("hp",   110.0,  0.7071, -3.0103),
    ("peak", 170.0,  1.0,     7.0),
    ("peak", 500.0,  1.0,    -3.0),
    ("peak", 2000.0, 1.2,    -5.0),
    ("peak", 7000.0, 0.7,     4.0),
    ("lp",   19000.0, 0.7071, -3.0103),
]


def biquad(kind, f0, q, gain_db, sr):
    """Koefficienty RBJ cookbook."""
    w0 = 2.0 * math.pi * f0 / sr
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "peak":
        A = 10 ** (gain_db / 40.0)
        b0, b1, b2 = 1 + alpha * A, -2 * cw, 1 - alpha * A
        a0, a1, a2 = 1 + alpha / A, -2 * cw, 1 - alpha / A
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    else:  # lp
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def biquad_db(coef, f, sr):
    b0, b1, b2, a1, a2 = coef
    w = 2.0 * math.pi * f / sr
    cw1, sw1 = math.cos(-w), math.sin(-w)
    cw2, sw2 = math.cos(-2 * w), math.sin(-2 * w)
    nr = b0 + b1 * cw1 + b2 * cw2
    ni = b1 * sw1 + b2 * sw2
    dr = 1.0 + a1 * cw1 + a2 * cw2
    di = a1 * sw1 + a2 * sw2
    num = math.sqrt(nr * nr + ni * ni)
    den = math.sqrt(dr * dr + di * di)
    return 20.0 * math.log10(num / den) if den > 0 and num > 0 else -200.0


def designed_raw_db(f, sr=48000):
    total = 0.0
    for kind, f0, q, g in EQ_BANDS:
        total += biquad_db(biquad(kind, f0, q, g, sr), f, sr)
    return total


# Izmereniya normiruyutsya po REF_BAND, znachit i zadumannuyu krivuyu nado
# normirovat po ney zhe - inache promah budet zavyshen na postoyannuyu velichinu.
_REF_OFFSET = sum(designed_raw_db(float(f)) for f in FREQS
                  if REF_BAND[0] <= f <= REF_BAND[1]) /               len([f for f in FREQS if REF_BAND[0] <= f <= REF_BAND[1]])


def designed_db(f, sr=48000):
    return designed_raw_db(f, sr) - _REF_OFFSET


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


def levels(path):
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
    out = {}
    for i, f in enumerate(FREQS):
        t0 = base + int(sr * (i * (TONE_S + GAP_S) + skip))
        t1 = t0 + int(sr * ANALYZE_S)
        out[f] = db(goertzel(s[t0:t1], sr, float(f))) if t1 <= len(s) else None
    return out, db(floor)


def normalize(lv):
    ref = [v for f, v in lv.items() if v is not None and REF_BAND[0] <= f <= REF_BAND[1]]
    base = sum(ref) / len(ref)
    return {f: (v - base if v is not None else None) for f, v in lv.items()}, base


def main():
    p_eq, p_stock = sys.argv[1], sys.argv[2]
    lv_eq, floor_eq = levels(p_eq)
    lv_st, floor_st = levels(p_stock)
    rel_eq, base_eq = normalize(lv_eq)
    rel_st, base_st = normalize(lv_st)

    print("  s ekvalayzerom: %s   (opora %.1f dB, shum %.1f dB)" % (p_eq, base_eq, floor_eq))
    print("  bez nego:       %s   (opora %.1f dB, shum %.1f dB)" % (p_stock, base_st, floor_st))
    print("  normirovka po %d-%d Gts; dostoverno %d-%d Gts" % (REF_BAND + TRUST_BAND))
    print()
    print("  %-7s %9s %9s %9s %9s %9s" % ("Gts", "bez EQ", "s EQ", "raznica", "zadumano", "promah"))
    print("  " + "-" * 62)
    for f in FREQS:
        a, b = rel_st.get(f), rel_eq.get(f)
        lo_a, lo_b = lv_st.get(f), lv_eq.get(f)
        if a is None or b is None:
            continue
        weak = (lo_a - floor_st < 10) or (lo_b - floor_eq < 10)
        trusted = TRUST_BAND[0] <= f <= TRUST_BAND[1] and not weak
        d = b - a
        want = designed_db(float(f))
        miss = d - want
        note = "" if trusted else "   (ne doveryat)"
        print("  %-7d %9.1f %9.1f %9.1f %9.1f %9.1f%s" % (f, a, b, d, want, miss, note))
    print("  " + "-" * 62)
    print()
    ok = [(f, rel_eq[f] - rel_st[f] - designed_db(float(f))) for f in FREQS
          if TRUST_BAND[0] <= f <= TRUST_BAND[1] and rel_eq.get(f) is not None
          and rel_st.get(f) is not None
          and (lv_st[f] - floor_st) >= 10 and (lv_eq[f] - floor_eq) >= 10]
    if ok:
        err = [abs(e) for _, e in ok]
        print("  V dostovernoy polose: sredniy promah %.1f dB, hudshiy %.1f dB (na %d Gts)"
              % (sum(err) / len(err), max(err), max(ok, key=lambda t: abs(t[1]))[0]))


if __name__ == "__main__":
    main()
