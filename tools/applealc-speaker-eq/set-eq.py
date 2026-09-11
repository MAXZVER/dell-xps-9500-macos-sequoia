"""Perezapisyvaet blok Filter u DspEqualization32 v layout13.xml zadannymi polosami.

Pravka hirurgicheskaya, po strokam: plistlib pereformatiroval by ves fayl i razdul
patch dlya repozitoriya do neuznavaemosti.

Format zapisi polosy (chislovye klyuchi):
  2 - nabor parametrov (vsegda 2)
  3 - nomer polosy 0..31
  4 - kanal (0 = oba)
  5 - tip: 0 = FNCh, 1 = FVCh, 4 = parametricheskiy
  6 - chastota      | bitovoe predstavlenie float kak znakovoe 32-bitnoe celoe
  7 - dobrotnost Q  |
  8 - usilenie v dB |
"""
import struct, sys

# (nomer polosy, tip, chastota, Q, usilenie dB)
BANDS = [
    (0,  1, 110.0,   0.7071, -3.0103),   # FVCh: nizhe dinamiki tolko hodyat, no ne igrayut
    (4,  4, 170.0,   0.9,     8.0),      # podyom niza
    (10, 4, 630.0,   2.0,     4.0),      # chastichnaya zasypka provala stykа polos
    (18, 4, 1800.0,  1.0,    -7.0),      # pik 1250-2000: samaya nadezhno izmerennaya detal
    (24, 4, 7000.0,  0.7,     4.0),      # verh; proverit na nashem stende nelzya
    (31, 0, 19000.0, 0.7071, -3.0103),   # FNCh
]


def f2i(x):
    """float -> ego bitovoe predstavlenie kak znakovoe 32-bitnoe celoe."""
    return struct.unpack("<i", struct.pack("<f", x))[0]


def build_array(indent_array):
    ti = indent_array            # tabulyaciya pered <array>
    td = ti + "\t"               # <dict>
    tk = td + "\t"               # klyuchi
    out = [ti + "<array>"]
    for band, kind, freq, q, gain in BANDS:
        out.append(td + "<dict>")
        for key, val in (("2", 2), ("3", band), ("4", 0), ("5", kind),
                         ("6", f2i(freq)), ("7", f2i(q)), ("8", f2i(gain))):
            out.append(tk + "<key>%s</key>" % key)
            out.append(tk + "<integer>%d</integer>" % val)
        out.append(td + "</dict>")
    out.append(ti + "</array>")
    return out


def main():
    path = sys.argv[1]
    lines = open(path, encoding="utf-8", newline="").read().split("\n")

    # Nahodim DspEqualization32, potom pervyy posle nego <key>Filter</key>
    eq = next(i for i, l in enumerate(lines) if "DspEqualization32" in l)
    fk = next(i for i in range(eq, len(lines)) if "<key>Filter</key>" in lines[i])
    start = next(i for i in range(fk, len(lines)) if "<array>" in lines[i])
    depth = 0
    end = None
    for i in range(start, len(lines)):
        if "<array>" in lines[i]:
            depth += 1
        if "</array>" in lines[i]:
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None:
        sys.exit("  ne nashel konec massiva Filter")

    indent = lines[start][:len(lines[start]) - len(lines[start].lstrip("\t"))]
    new = build_array(indent)
    old_count = end - start + 1

    lines[start:end + 1] = new
    open(path, "w", encoding="utf-8", newline="").write("\n".join(lines))

    print("  zamenil stroki %d..%d (%d -> %d)" % (start + 1, end + 1, old_count, len(new)))
    print("  polos: %d" % len(BANDS))
    names = {0: "FNCh", 1: "FVCh", 4: "param"}
    for band, kind, freq, q, gain in BANDS:
        print("    polosa %2d  %-5s %8.0f Gts  Q=%.4f  %+.2f dB" %
              (band, names.get(kind, kind), freq, q, gain))


if __name__ == "__main__":
    main()
