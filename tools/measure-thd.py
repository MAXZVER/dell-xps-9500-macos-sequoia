import wave, struct, math, sys
def goertzel(s, sr, f):
    n=len(s); k=int(0.5+n*f/sr); w=2*math.pi*k/n; c=2*math.cos(w); s1=s2=0.0
    for x in s:
        s0=x+c*s1-s2; s2=s1; s1=s0
    return math.sqrt(max(s1*s1+s2*s2-c*s1*s2,0))/(n/2)
fn=sys.argv[1]; f0=float(sys.argv[2])
w=wave.open(fn,'r'); n=w.getnframes(); sr=w.getframerate(); ch=w.getnchannels()
d=w.readframes(n); w.close()
v=struct.unpack('<%dh'%(len(d)//2), d)
if ch>1: v=v[0::ch]
s=[x/32768.0 for x in v]
# ishchem okno 1.5 sek s maksimalnoy energiey
win=int(sr*1.5); step=int(sr*0.1)
best=None; bi=0
if len(s)>win:
    for i in range(0, len(s)-win, step):
        e=sum(x*x for x in s[i:i+win:8])
        if best is None or e>best: best=e; bi=i
    seg=s[bi:bi+win]
else:
    seg=s
mags=[goertzel(seg,sr,f0*k) for k in (1,2,3)]
db=lambda m: 20*math.log10(m) if m>1e-12 else -200
h=math.sqrt(mags[1]**2+mags[2]**2)
thd=100*h/mags[0] if mags[0]>1e-9 else 0
rms=math.sqrt(sum(x*x for x in seg)/len(seg))
print("f0=%6.1f dB  h2=%6.1f  h3=%6.1f  THD=%5.1f%%  RMS=%6.1f dB  t=%.1fs" %
      (db(mags[0]), db(mags[1]), db(mags[2]), thd, db(rms), bi/sr))
