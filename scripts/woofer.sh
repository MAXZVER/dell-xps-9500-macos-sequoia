#!/bin/bash
#
# Ton-kontrol dlya dinamikov Dell XPS 15 9500 na macOS.
#
# Kodek ALC289 vedyot dve pary dinamikov s ochen raznymi harakteristikami:
#   uzel 0x14 (CAP 0x02) - verhnyaya para: pik na 2 kGc, nizhe 200 Gc nichego
#   uzel 0x17 (CAP 0x03) - nizhnyaya para: rabotaet 120 Gc - 1 kGc, vverhu slabee
#
# macOS dvigaet usilenie oboih CAP sinhronno s regulyatorom gromkosti. Derzha
# mezhdu nimi postoyannuyu raznicu, poluchaem apparatnyy ton-kontrol bez
# storonnego softa: verhnyaya tishe -> menshe rezkosti na 2 kGc i bolshe basa
# po balansu.
#
# Izmereno vneshnim mikrofonom: priglushenie verhney pary na 12 shagov ronyaet
# 2 kGc na 4.6 dB, a 500 Gc vsego na 1.1 dB - potomu chto 500 Gc otdayot
# drugaya para. Eto tochechnyy srez pika rezkosti.
#
# Trebuet: pin config uzla 0x17 (v Info.plist AppleALC), boot-arg alcverbs=1,
# utilitu alc-verb v /usr/local/bin.

A=/usr/local/bin/alc-verb
LOG=/var/log/woofer.log

SPREAD=8         # na skolko shagov (po 0.75 dB) nizhnyaya para gromche verhney.
                 # Edinstvennaya ruchka tembra, odinakovaya na lyuboy gromkosti.
                 # Ranshe skladyvalis "podyom nizhney" i "priglushenie verhney",
                 # i razbros vyhodil 18 dB na tihoy (gudelo) i 6 dB na gromkoy
                 # (zvuchalo horosho) - poetomu teper odna velichina.
                 # 4 shaga pochti ne slyshno, 8 - horosho, 12 - glohnet verh
                 # (-6.7 dB na 4 kGc, izmereno).

CAP=0x52         # potolok nizhney pary: vyshe na 120 Gc rezko rastut iskazheniya
                 # (57% THD na 0x57 - dinamik uhodit v otboy).

FLOOR=0x20       # nizhe ne opuskat verhnyuyu paru - zashchita ot tishiny.

log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }
v(){ sudo -n "$A" "$1" "$2" "$3" 2>/dev/null | tail -1; }

sleep 25
log "start: SPREAD=$SPREAD CAP=$CAP FLOOR=$FLOOR"

while true; do
  g2=$(v 0x02 0xb 0x8000)
  g3=$(v 0x03 0xb 0x8000)

  # Pravim TOLKO kogda oba CAP chitayutsya odinakovo: eto priznak togo, chto
  # znachenie tolko chto vystavila macOS po regulyatoru gromkosti. Esli oni
  # uzhe razvedeny - nasha pravka na meste, nichego ne delaem.
  #
  # Vychislyat "sistemnuyu gromkost" iz etih zhe registrov nelzya: demon sam v
  # nih pishet, poluchaetsya zamknutyy krug. Na pervom zhe nevernom chtenii
  # (alc-verb inogda vozvrashchaet 0x00000000 pri igrayushchem zvuke) oba
  # usileniya uezzhayut v nol i mashina zamolkaet. Proveryali.
  if [ -n "$g2" ] && [ "$g2" = "$g3" ]; then
    want=$(/usr/bin/python3 -c "
try:
    s = int('$g2', 16) & 0x7f
except Exception:
    raise SystemExit
if s < int('$FLOOR', 16):
    raise SystemExit
lo = min(s, $CAP)
# verhnyuyu privyazyvaem k nizhney, a ne k regulyatoru: inache na 100%
# gromkosti nizhnyaya upiraetsya v CAP, a verhnyaya prodolzhaet rasti, i
# razbros s +6 dB padaet do +2 dB - tembr menyaetsya na maksimume.
hi = max(lo - $SPREAD, int('$FLOOR', 16))
print('0x%02x 0x%02x' % (lo, hi))
" 2>/dev/null)
    if [ -n "$want" ]; then
      set -- $want
      v 0x03 0x300 $((0xb000 | $1)) >/dev/null
      v 0x02 0x300 $((0xb000 | $2)) >/dev/null
      log "gromkost $g2 -> nizhnie $1, verhnie $2 (razbros $SPREAD shagov)"
    fi
  fi

  # posle probuzhdeniya pin uzla 0x17 inogda sbrasyvaetsya - vosstanavlivaem
  if [ "$(v 0x17 0xf1c 0)" = "0x411111f0" ]; then
    v 0x17 0x71c 0x11 >/dev/null; v 0x17 0x71d 0x01 >/dev/null
    v 0x17 0x71e 0x17 >/dev/null; v 0x17 0x71f 0x90 >/dev/null
    log "pin 0x17 vosstanovlen"
  fi

  sleep 3
done
