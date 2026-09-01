# LED + persistência em modo XINPUT (libusb, root). Protocolo: XinputCommand/XInputDataUtils + flydigictl/xinput.
# uso: sudo venv/bin/python xinput_led.py show | brightness N | save
import usb.core, usb.util, time, sys
def crc(p): p=bytearray(p); p[-1]=sum(p[:-1])&0xff; return bytes(p)
def cmd(c,*a): p=bytearray(15); p[0]=165; p[1]=c; p[2:2+len(a)]=bytes(a); return crc(p)
d=usb.core.find(idVendor=0x045e, idProduct=0x028e) or sys.exit("controle não está em XInput")
try: d.detach_kernel_driver(0)
except Exception: pass
usb.util.claim_interface(d,0)
def rx(secs, pred):
    t=time.time()
    while time.time()-t<secs:
        try: r=bytes(d.read(0x81,64,timeout=200))
        except usb.core.USBTimeoutError: continue
        if len(r)>20 and r[14]==165 and pred(r): return r
def led_read(cfg=0):
    d.write(0x05, cmd(38,cfg)); parts={}; t=time.time()
    while time.time()-t<3 and len(parts)<50:
        r=rx(0.5, lambda r: r[15]==39)
        if r: parts[r[16]]=r[17:27]
    return b''.join(parts[i] for i in sorted(parts))
def cfg_read(cfg=0):
    d.write(0x05, cmd(33,cfg)); parts={}; t=time.time()
    while time.time()-t<4 and len(parts)<79:
        r=rx(0.5, lambda r: r[15]==34)
        if r: parts[r[16]]=r[17:27]
    return b''.join(parts[i] for i in sorted(parts))
def cfg_write(blob, cfg=0):
    N=79; acks=0
    d.write(0x05, cmd(37,N,160,cfg))
    if rx(1.5, lambda r: r[15] in (35,37)): acks+=1
    for i in range(N):
        d.write(0x05, crc(bytes([165,36])+blob[i*10:(i+1)*10].ljust(10,b'\0')+bytes([160,i,0])))
        if rx(1, lambda r: r[15]==36): acks+=1
    return acks, N+1
def led_write(blob, cfg=0):
    N=(len(blob)+9)//10; acks=0
    d.write(0x05, cmd(42,cfg,N)); 
    if rx(1, lambda r: r[15] in (42,41,35,37)): acks+=1
    for i in range(N):
        d.write(0x05, crc(bytes([165,41])+blob[i*10:(i+1)*10].ljust(10,b'\0')+bytes([160,i,0])))
        if rx(1, lambda r: r[15]==41): acks+=1
    return acks, N+1
def save_flash(cfg=0):
    d.write(0x05, cmd(80,2,cfg)); r=rx(2, lambda r: r[15]==80 and r[16]==2)
    if not r: return "sem resposta ao ReadRandomId"
    rid=(r[17]<<8)|r[18]; new=(rid+1)&0xffff; print(f"  randomId atual={rid} (cfg {r[19]}) → salvando com {new}")
    d.write(0x05, cmd(80,3,new>>8,new&0xff)); r=rx(3, lambda r: r[15]==80 and r[16]==3)
    return f"SaveFlash status={'OK' if r and r[17]==1 else ('falhou raw=%s'%r[14:22].hex() if r else 'sem resposta')}"
a=sys.argv[1:]
blob=led_read(); h=blob[:20]
print(f"LED: {len(blob)}B mode={h[8]} speed={h[5]} brightness={h[6]} groups={h[7]}")
if a and a[0]=='brightness':
    b=bytearray(blob); b[6]=int(a[1])
    cfg=cfg_read(); assert len(cfg)==790, "config incompleta"
    print("config re-write ACKs %d/%d"%cfg_write(cfg)); time.sleep(0.5)   # pré-requisito do firmware em XInput
    print("LED write ACKs %d/%d"%led_write(bytes(b))); time.sleep(0.5)
    print("re-leitura brightness =", led_read()[6])
if a and a[0] in ('save','brightness'): print(save_flash())
usb.util.release_interface(d,0)
try: d.attach_kernel_driver(0)
except Exception: pass
