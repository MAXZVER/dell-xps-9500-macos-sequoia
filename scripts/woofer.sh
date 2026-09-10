#!/bin/bash
# Ton-kontrol dlya dinamikov Dell XPS 15 9500 na macOS.
#
# Kodek ALC289 imeet dve pary dinamikov s ochen raznymi harakteristikami:
#   uzel 0x14 (CAP 0x02) - verhnyaya para: pik na 2 kGc, nizhe 200 Gc nichego
#   uzel 0x17 (CAP 0x03) - nizhnyaya para: rabotaet 120 Gc - 1 kGc, vverhu slabee
#
# macOS dvigaet usilenie oboih CAP sinhronno s gromkostyu. Derzha ih na
# fiksirovannom rasstoyanii drug ot druga, poluchaem apparatnyy ton-kontrol:
# nizhnyaya gromche -> bolshe basa, verhnyaya tishe -> menshe rezkosti na 2 kGc.
#
# Izmereno vneshnim mikrofonom: priglushenie verhney pary na 12 shagov ronyaet
# 2 kGc na 4.6 dB, a 500 Gc vsego na 1.1 dB - eto tochechnyy srez pika rezkosti.
#
# Trebuet: pin config uzla 0x17 (v Info.plist AppleALC), boot-arg alcverbs=1,
# utilitu alc-verb.

A=/usr/local/bin/alc-verb
LOG=/var/log/woofer.log

OFFSET=16        # na skolko shagov (po 0.75 dB) nizhnyaya para gromche sistemnoy gromkosti
CAP=0x48         # potolok PODYOMA nizhney pary: na 200 Gc uroven nasyshchaetsya imenno zdes,
                 # vyshe podnimaetsya tolko seredina 300-1000 Gc - "korobochnost"
ATTEN=4          # na skolko shagov tishe verhnyaya para: srezaet pik 2 kGc,
                 # no bolshe 4-5 shagov zametno gubit verh na 4 kGc (0 = ne trogat)

log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }
v(){ sudo -n "$A" "$1" "$2" "$3" 2>/dev/null | tail -1; }

sleep 25
log "start: OFFSET=$OFFSET CAP=$CAP ATTEN=$ATTEN"

FLOOR=0x20       # nikogda ne opuskat nizhe - zashchita ot tishiny

while true; do
  g2=$(v 0x02 0xb 0x8000)
  g3=$(v 0x03 0xb 0x8000)

  # Pravim TOLKO kogda oba CAP ravny: eto znachit, chto znachenie tolko chto
  # vystavila macOS po polozheniyu regulyatora gromkosti. Esli oni uzhe
  # razvedeny - nasha pravka na meste, nichego ne delaem.
  #
  # Vychislyat "sistemnuyu gromkost" iz etih zhe registrov nelzya: demon sam
  # ih menyaet, poluchaetsya zamknutyy krug, i pri lyubom rassinhrone znachenie
  # uezzhaet v nol. Proveryali - zvuk propadaet.
  if [ -n "$g2" ] && [ "$g2" = "$g3" ]; then
    want=$(/usr/bin/python3 -c "
try:
    s=int('$g2',16)&0x7f
except Exception:
    raise SystemExit
if s < int('$FLOOR',16):
    raise SystemExit
# potolok ogranichivaet PODYOM, no nikogda ne opuskaet nizhe sistemnogo urovnya
lo=max(s, min(s+$OFFSET, $CAP))
hi=max(s-$ATTEN, int('$FLOOR',16))
print('0x%02x 0x%02x' % (lo, hi))
" 2>/dev/null)
    if [ -n "$want" ]; then
      set -- $want
      v 0x03 0x300 $((0xb000 | $1)) >/dev/null
      v 0x02 0x300 $((0xb000 | $2)) >/dev/null
      log "gromkost $g2 -> nizhnie $1, verhnie $2"
    fi
  fi

  # esli pin uzla 0x17 sbrosilsya (byvaet posle probuzhdeniya) - vklyuchaem
  if [ "$(v 0x17 0xf1c 0)" = "0x411111f0" ]; then
    v 0x17 0x71c 0x11 >/dev/null; v 0x17 0x71d 0x01 >/dev/null
    v 0x17 0x71e 0x17 >/dev/null; v 0x17 0x71f 0x90 >/dev/null
    log "pin 0x17 vosstanovlen"
  fi

  sleep 3
done
