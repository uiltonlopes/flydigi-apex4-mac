# Upload de GIF/imagem pra tela do Apex 4 em modo XINPUT (libusb, root). Protocolo = ScreenDataK2TransService do Space Station.
# uso: sudo venv/bin/python sudo_screen.py arquivo.gif|frame.bin [--go] [--frames N]
import usb.core, usb.util, time, sys, os
if len(sys.argv)>1 and sys.argv[1]=='ledexp':
    sys.argv=[sys.argv[0]]+sys.argv[2:]; exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'xinput_led_exp.py')).read()); sys.exit(0)
if len(sys.argv)>1 and sys.argv[1]=='led':  # subcomando led -> xinput_led.py (mesma regra de sudo)
    sys.argv=[sys.argv[0]]+sys.argv[2:]; exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'xinput_led.py')).read()); sys.exit(0)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
def crc(p, start=0): p=bytearray(p); p[-1]=sum(p[start:-1])&0xff; return bytes(p)
src=sys.argv[1]; go='--go' in sys.argv; CH=26
if src.lower().endswith('.bin'): frames=[open(src,'rb').read()]; delay_cs=10
else:
    from apex4 import Apex4
    frames, delay_cs = Apex4.gif_to_bins(src)
if '--frames' in sys.argv: frames=frames[:int(sys.argv[sys.argv.index('--frames')+1])]
N=len(frames); print(f"{N} frame(s) de {len(frames[0])} B, delay {delay_cs*10} ms, go={go}")
d=usb.core.find(idVendor=0x045e, idProduct=0x028e) or sys.exit("controle não está em XInput (045e:028e)")
try: d.detach_kernel_driver(0)
except Exception as e: print("detach:", e)
usb.util.claim_interface(d,0)
def rx(secs, want):
    t=time.time()
    while time.time()-t<secs:
        try: r=bytes(d.read(0x81,64,timeout=200))
        except usb.core.USBTimeoutError: continue
        if len(r)>20 and r[14]==90 and r[15]==165 and r[16] in want: return r
    return None
def tx(pkt, tries=50):
    for i in range(tries):
        try: d.write(0x05, bytes(pkt), timeout=500); return
        except usb.core.USBTimeoutError: time.sleep(0.1)
    raise SystemExit("write travou")
t0=time.time()
for num, fr in enumerate(frames, 1):
    size=len(fr)
    # GetPicStartTransCmd (XInput): [165,208,9,1,gifType=1,gifNum,num,2,sizeHi,sizeLo,crc(1..9)]
    start=bytearray([165,208,9,1,1,N,num,2,size>>8,size&0xff,0,0,0,0,0]); start[10]=sum(start[1:10])&0xff
    if not go: print(f"frame {num}/{N}: start={bytes(start).hex()}"); continue
    tx(start); a=rx(3,(208,209))
    if a is None: sys.exit(f"frame {num}: sem ACK do start")
    sent=0
    while sent<size:
        pkt=crc(bytearray([165,209,sent>>8,sent&0xff])+fr[sent:sent+CH].ljust(CH,b'\xff')+b'\0',1)
        tx(pkt); a=rx(1.5,(209,))
        if a is None: sys.exit(f"frame {num}: sem ACK no offset {sent}")
        if a[18]!=0: print(f"  ret={a[18]} no offset {sent} — reenviando"); continue
        sent+=min(CH,size-sent)
    end=bytearray([165,210,7,1,num,sent>>8,sent&0xff,0,0,0,0,0,0,0,0]); end[8]=sum(end[1:8])&0xff
    tx(end); a=rx(3,(210,211))
    print(f"frame {num}/{N} OK ({sent} B, ack={'%d ret=%d'%(a[16],a[18]) if a else 'nenhum'}) t={time.time()-t0:.1f}s")
if go:
    endall=bytearray([165,211,7,1,N,0,0,0,0,0,0,0,0,0,0]); endall[8]=sum(endall[1:8])&0xff
    tx(endall); a=rx(3,(210,211)); print("EndAll:", a[14:24].hex() if a else "sem ack", f"| total {time.time()-t0:.1f}s")
usb.util.release_interface(d,0)
try: d.attach_kernel_driver(0)
except Exception: pass
