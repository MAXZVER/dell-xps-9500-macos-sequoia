import wave, struct, math, sys
def goertzel(s, sr, f):
    n=len(s); k=int(0.5+n*f/sr); w=2*math.pi*k/n; c=2*math.cos(w); s1=s2=0.0
    for x in s:
        s0=x+c*s1-s2; s2=s1; s1=s0
    return math.sqrt(max(s1*s1+s2*s2-c*s1*s2,0))/(n/2)
w=wave.open(sys.argv[1],'r'); n=w.getnframes(); sr=w.getframerate(); ch=w.getnchannels()
d=w.readframes(n); w.close()
v=struct.unpack('<%dh'%(len(d)//2), d)
if ch>1: v=v[0::ch]
s=[x/32768.0 for x in v]
cut=int(sr*0.4); s=s[cut:len(s)-cut] if len(s)>2*cut else s
f0=float(sys.argv[2])
mags=[goertzel(s,sr,f0*k) for k in (1,2,3)]
db=lambda m: 20*math.log10(m) if m>1e-12 else -200
h=math.sqrt(mags[1]**2+mags[2]**2)
thd = 100*h/mags[0] if mags[0]>1e-9 else 0
print("f0=%6.1f dB  h2=%6.1f  h3=%6.1f  THD=%5.1f%%" % (db(mags[0]), db(mags[1]), db(mags[2]), thd))
