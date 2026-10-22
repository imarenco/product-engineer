# Lists every write to MMKV keys containing <substring>, oldest first; the last line is the live value.
# Usage: python3 -I drivers/react-native/mmkv.py <mmkv.default> <substring>
import sys,struct
if len(sys.argv)!=3: sys.exit('usage: python3 -I drivers/react-native/mmkv.py <mmkv.default> <substring>')
data=open(sys.argv[1],'rb').read(); want=sys.argv[2]
if len(data)<4: sys.exit(f'{sys.argv[1]}: empty or not an MMKV file')
size=struct.unpack('<I',data[:4])[0]; buf=data[4:4+size]
def varint(b,i):
    r=s=0
    while True:
        c=b[i]; i+=1; r|=(c&0x7f)<<s; s+=7
        if c<0x80: return r,i
i=0
# MMKV's first record is a placeholder varint
try:
    _,i=varint(buf,i)
except Exception: pass
out=[]
while i<len(buf):
    try:
        kl,i=varint(buf,i); k=buf[i:i+kl]; i+=kl
        vl,i=varint(buf,i); v=buf[i:i+vl]; i+=vl
    except Exception: break
    k=k.decode('utf8','replace')
    if want in k:
        # strings carry their own length prefix; numbers are 8-byte doubles (react-native-mmkv stores every
        # number as a double); booleans are a bare varint (0 = false or '')
        val=None
        try:
            sl,j=varint(v,0)
            if len(v)>1 and j+sl==len(v): val=v[j:j+sl].decode('utf8')
        except Exception: pass
        if val is None and len(v)==8: val=repr(struct.unpack('<d',v)[0])
        if val is None:
            try: val=str(varint(v,0)[0])
            except Exception: val=repr(v)
        out.append(f'{k} = {val}')
for n,v in enumerate(out): print(n,v)
