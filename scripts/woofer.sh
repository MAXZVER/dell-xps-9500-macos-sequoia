#!/bin/bash
# Nizkochastotnye dinamiki Dell XPS 15 9500 na macOS.
#
# Kodek ALC289: uzel 0x14 - tvitery (rabotayut iz korobki), uzel 0x17 -
# nizkochastotnye, kotorye proshivka Dell obyavlyaet neispolzuemymi
# (pin config 0x411111f0). Zdes my ih vklyuchaem i sazhaem na otdelnyy
# CAP 0x03, chtoby derzhat ih gromche tviterov na fiksirovannuyu velichinu.
#
# Trebuet: boot-arg alcverbs=1 i utilitu alc-verb.

A=/usr/local/bin/alc-verb
LOG=/var/log/woofer.log
OFFSET=16        # shagov po 0.75 dB nad urovnem tviterov (~ +12 dB)
CAP=0x52         # potolok po izmereniyam: na 200 Gc uroven nasyshchaetsya uzhe k 0x48,
                 # a na 120 Gc vyshe 0x52 rezko rastut iskazheniya (57% THD na 0x57).

log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }
v(){ sudo -n "$A" "$1" "$2" "$3" 2>/dev/null | tail -1; }

enable_woofer(){
  v 0x17 0x71c 0x30   >/dev/null   # pin config -> 0x90170130 (Speaker)
  v 0x17 0x71d 0x01   >/dev/null
  v 0x17 0x71e 0x17   >/dev/null
  v 0x17 0x71f 0x90   >/dev/null
  v 0x17 0x701 0x01   >/dev/null   # istochnik: CAP 0x03
  v 0x17 0x707 0x40   >/dev/null   # razreshit vyhod
  v 0x17 0x300 0xb000 >/dev/null   # snyat priglushenie
}

sleep 25
enable_woofer
log "vklyucheno pri starte, pin control = $(v 0x17 0xf07 0)"

while true; do
  pinctl=$(v 0x17 0xf07 0)
  if [ "$pinctl" != "0x00000040" ]; then
    enable_woofer
    log "vosstanovleno posle sbrosa (bylo $pinctl)"
  fi

  # derzhim 0x03 gromche 0x02 na OFFSET, no ne vyshe CAP
  cur02=$(v 0x02 0xb 0x8000)
  cur03=$(v 0x03 0xb 0x8000)
  want=$(/usr/bin/python3 -c "
try:
    g=int('$cur02',16)&0x7f
except Exception:
    raise SystemExit
print('0x%02x' % min(g+$OFFSET, $CAP))
" 2>/dev/null)
  if [ -n "$want" ] && [ "$(printf '0x%08x' $((want)) )" != "$cur03" ]; then
    v 0x03 0x300 $((0xb000 | want)) >/dev/null
  fi
  sleep 3
done
