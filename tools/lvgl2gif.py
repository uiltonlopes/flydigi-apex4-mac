#!/usr/bin/env python3
"""Convert an Apex 4 screen animation (concatenated LVGL frames: 4-byte header + 160x80 RGB565 big-endian)
into an animated GIF. Used once to turn Space Station's factory `default_screen_image_<id>.bin` files into
the previews the app shows as "On the controller" before anything was sent from this Mac.

    python3 tools/lvgl2gif.py in.bin out.gif [interval_ms]
"""
import struct, sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
interval = int(sys.argv[3]) if len(sys.argv) > 3 else 100
data = open(src, "rb").read()
frames, pos = [], 0
while pos + 4 <= len(data):
    hdr = struct.unpack_from("<I", data, pos)[0]
    cf, w, h = hdr & 0x1F, (hdr >> 10) & 0x7FF, (hdr >> 21) & 0x7FF
    n = w * h * 2
    px = data[pos + 4:pos + 4 + n]
    if cf != 4 or len(px) < n:
        break
    img = Image.new("RGB", (w, h))
    out = bytearray(w * h * 3)
    for i in range(w * h):
        v = (px[2 * i] << 8) | px[2 * i + 1]
        out[3 * i] = ((v >> 11) & 0x1F) << 3
        out[3 * i + 1] = ((v >> 5) & 0x3F) << 2
        out[3 * i + 2] = (v & 0x1F) << 3
    img.frombytes(bytes(out))
    frames.append(img)
    pos += 4 + n
if not frames:
    sys.exit("no LVGL frames found")
frames[0].save(dst, save_all=True, append_images=frames[1:], duration=interval, loop=0, optimize=True)
print(f"{dst}: {len(frames)} frames {frames[0].size}")
