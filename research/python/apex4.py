#!/usr/bin/env python3
"""apex4 — protótipo macOS pra Flydigi Apex 4 (modo DInput, HID if2, sem root).
Protocolo reverso do Flydigi Space Station 3.4.4.3 (GameController.ServiceHandler + LibCommon) e do flydigictl.
Uso:
  apex4.py info                      # DeviceInfo
  apex4.py led                       # mostra config de LED
  apex4.py led brightness N          # 0-100
  apex4.py led steady RRGGBB         # cor fixa
  apex4.py led mode M                # 0 off,1 streamlined,2 breathing,3 gradient,4 feedback,5 steady
  apex4.py gif2bin arquivo.gif dir/  # só converte (LVGL bin por frame)
  apex4.py screen arquivo.gif [--go] # upload da tela (sem --go = dry-run: só mostra os pacotes)
"""
import hid, sys, time, struct, os
VID, PID, IFACE = 0x04b4, 0x2412, 2
SCREEN_W, SCREEN_H, MAX_FRAMES = 160, 80, 35
CHUNK = 26                      # XinputCommand.K2PerPackageDataLength

def crc_from(pkt, start):       # XinputCommand.CrcData(data, start): último byte = soma dos anteriores a partir de start
    b = bytearray(pkt); b[-1] = sum(b[start:-1]) & 0xff; return bytes(b)

class Apex4:
    def __init__(s, verbose=False):
        p = [h['path'] for h in hid.enumerate(VID, PID) if h['interface_number'] == IFACE]
        if not p: sys.exit("Apex 4 não encontrado em modo DInput (04b4:2412). Cabo USB + modo DInput.")
        s.d = hid.device(); s.d.open_path(p[0]); s.d.set_nonblocking(True); s.v = verbose
    def tx(s, pkt, retries=120):
        if s.v: print("  tx", pkt.hex())
        for i in range(retries):
            n = s.d.write(bytes(pkt))
            if n >= 0: 
                if i and s.v: print(f"  (ok após {i} retries)")
                return
            err = s.d.error(); time.sleep(0.5)
        raise IOError(err)
    def rx(s, secs):
        t = time.time()
        while time.time() - t < secs:
            r = bytes(s.d.read(64))
            if r: 
                if s.v and (len(r) < 16 or r[15] != 0): print("  rx", r.hex())
                yield r
            else: time.sleep(0.002)
    # ---- comandos DInput simples: report 5 + [cmd, args] (12 bytes)
    def cmd5(s, c, *a):
        p = bytearray(12); p[0] = 5; p[1] = c; p[2:2+len(a)] = bytes(a); s.tx(p)
    def info(s):
        s.cmd5(236)
        for r in s.rx(2):
            if len(r) > 15 and r[15] == 236:
                fwl, fwh = r[9], r[10]
                return dict(deviceId=r[3], mac=r[5:9].hex(':'), fw=f"{fwh>>4}.{fwh&15}.{fwl>>4}.{fwl&15}", battery_raw=r[11], cpu=r[12], conn=r[13], motion=r[14])
    def read_blob(s, cmd, want_len):
        s.cmd5(cmd, 0); parts = {}
        for r in s.rx(3):
            if len(r) > 15 and r[15] == cmd: parts[r[3]] = r[5:15]
            if len(parts) * 10 >= want_len: break
        return b''.join(parts[i] for i in sorted(parts))
    def write_blob(s, header_cmd, data_cmd, data):
        N = (len(data) + 9) // 10
        s.tx(bytes([5, header_cmd, 0, N]).ljust(14, b'\0'))
        acks = 0
        for i in range(N):
            s.tx(bytes([5, data_cmd]) + data[i*10:(i+1)*10].ljust(10, b'\0') + bytes([160, i]))
            for r in s.rx(1):
                if len(r) > 15 and r[15] in (234, 231, 51): acks += 1; break
        return acks, N + 1
    # ---- LED (500 B: header 20 + 16 grupos x 10 unidades x RGB em %)
    def led_get(s): return s.read_blob(229, 500)
    def led_set(s, blob): return s.write_blob(231, 51, blob)
    # ---- tela
    @staticmethod
    def gif_to_bins(path):
        from PIL import Image, ImageSequence
        im = Image.open(path); frames = []; delays = []
        for fr in ImageSequence.Iterator(im):
            delays.append(fr.info.get('duration', 100))
            f = fr.convert('RGB')
            if f.size != (SCREEN_W, SCREEN_H): f = f.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
            px = f.tobytes(); out = bytearray()
            hdr = ((SCREEN_H << 11) | SCREEN_W) << 10 | 4      # lv_img_header_t: cf=4 TRUE_COLOR, w, h  (visto no lvImage2bin_x64.dll)
            out += struct.pack('<I', hdr)
            for i in range(0, len(px), 3):
                r = min(31, int(px[i] / 8 + 0.5)); g = min(63, int(px[i+1] / 4 + 0.5)); b = min(31, int(px[i+2] / 8 + 0.5))
                out += struct.pack('>H', (r << 11) | (g << 5) | b)   # RGB565 big-endian (rol bx,8 no DLL)
            frames.append(bytes(out))
            if len(frames) >= MAX_FRAMES: break
        delay_cs = max(1, (sum(delays) // len(delays)) // 10)       # GetGifDelay()/10 → centésimos
        return frames, delay_cs
    def screen_upload(s, frames, delay_cs, go=False):
        gif_type, gif_num = 1, len(frames)
        for num, fr in enumerate(frames, 1):
            size = len(fr)
            # DongleCommand.GetK2LedStartPicCmd: [5,165,208,9, 1,gifType,gifNum,num, freq*10/50, sizeHi, sizeLo, crc(2..)]
            start = bytearray([5, 165, 208, 9, 1, gif_type, gif_num, num, (delay_cs * 10 // 50) & 0xff, (size >> 8) & 0xff, size & 0xff, 0])
            start[11] = sum(start[2:11]) & 0xff
            print(f"frame {num}/{gif_num}: {size} B, start={bytes(start).hex()}")
            if not go: continue
            s.tx(start)
            if not s._wait_pic_ack(208): print("  sem ACK do start"); return False
            n2 = 1
            for r in s.rx(2.0):
                if len(r) > 7 and r[3] == 90 and r[4] == 165 and r[5] == 208: n2 += 1; print(f"  ack start #{n2} raw={r[3:12].hex()}")
            time.sleep(0.3)
            sent = 0
            while sent < size:
                chunk = fr[sent:sent+CHUNK].ljust(CHUNK, b'\xff')
                # ScreenDataK2TransService.GetPicTransDataCmd: [165,209,lenHi,lenLo, 26 dados, crc(from 1)] — no DInput embrulhado como report 5
                pkt = bytearray([5, 165, 209, (sent >> 8) & 0xff, sent & 0xff]) + chunk + b'\0'
                pkt = bytearray(crc_from(pkt, 2))
                s.tx(pkt)
                if not s._wait_pic_ack(209): print(f"  sem ACK no offset {sent}"); return False
                sent += min(CHUNK, size - sent)
            # fim do frame: GetPicEndCmd [165,210,7,1,num,lenHi,lenLo,0,crc(1..7)]
            end = bytearray([5, 165, 210, 7, 1, num, (sent >> 8) & 0xff, sent & 0xff, 0, 0]); end[9] = sum(end[2:9]) & 0xff
            s.tx(end)
            if not s._wait_pic_ack(210): print("  sem ACK do end"); return False
            print(f"  frame {num} OK ({sent} B)")
        if go:
            endall = bytearray([5, 165, 211, 7, 1, gif_num, 0, 0, 0, 0]); endall[9] = sum(endall[2:9]) & 0xff
            s.tx(endall); s._wait_pic_ack(211); print("EndAll enviado")
        return True
    def _wait_pic_ack(s, cmd, secs=1.0):
        # DInputDataManager: recBuf[3]==90 && recBuf[4]==165 && recBuf[5] in 208..211 ; ret=recBuf[7]
        for r in s.rx(secs):
            if len(r) > 7 and r[3] == 90 and r[4] == 165 and 208 <= r[5] <= 211:
                s._nack = getattr(s, '_nack', 0) + 1
                if r[5] != 209 or s._nack <= 4: print(f"  ack cmd={r[5]} ret={r[7]} raw={r[3:14].hex()}")
                return r[7] == 0 or True
        return False

if __name__ == '__main__':
    a = sys.argv[1:]
    if not a: print(__doc__); sys.exit(0)
    if a[0] == 'gif2bin':
        frames, d = Apex4.gif_to_bins(a[1]); os.makedirs(a[2], exist_ok=True)
        for i, f in enumerate(frames, 1): open(f"{a[2]}/{i}.bin", 'wb').write(f)
        print(f"{len(frames)} frames, {len(frames[0])} B cada, delay {d*10} ms"); sys.exit(0)
    g = Apex4(verbose='-v' in a)
    if a[0] == 'info': print(g.info())
    elif a[0] == 'led':
        blob = bytearray(g.led_get()); h = blob[:20]
        if len(a) == 1:
            modes = {0:"off",1:"streamlined",2:"breathing",3:"gradient",4:"feedback",5:"steady"}
            print(f"mode={h[8]} ({modes.get(h[8])}) speed={h[5]} brightness={h[6]} groups={h[7]}")
            for gi in range(h[7]): print(f"  g{gi}:", [tuple(blob[20+gi*30+u*3:20+gi*30+u*3+3]) for u in range(10) if any(blob[20+gi*30+u*3:20+gi*30+u*3+3])])
        else:
            if a[1] == 'brightness': blob[6] = int(a[2])
            elif a[1] == 'mode': blob[8] = int(a[2])
            elif a[1] == 'steady':
                r, gg, b = (int(a[2][i:i+2], 16) * 100 // 255 for i in (0, 2, 4)); blob[8] = 5
                for gi in range(h[7]):
                    blob[20+gi*30:20+gi*30+30] = bytes([r, gg, b]) + b'\0' * 27
            print("ACKs %d/%d" % g.led_set(bytes(blob)))
    elif a[0] == 'screen':
        frames, d = Apex4.gif_to_bins(a[1])
        if '--frames' in a: frames = frames[:int(a[a.index('--frames')+1])]
        print(f"{len(frames)} frames de {len(frames[0])} B, delay {d*10} ms; go={'--go' in a}")
        g.screen_upload(frames, d, go='--go' in a)
