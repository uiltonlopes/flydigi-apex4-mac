"""Enumera USB + HID e destaca o que pode ser o Apex 4."""
import usb.core, usb.util, hid, sys
KNOWN = {(0x045e,0x028e):"XInput (Xbox360 emul)", (0x04b4,0x2412):"Flydigi DInput (Cypress)"}
def s(dev, idx):
    try: return usb.util.get_string(dev, idx) or ""
    except Exception: return "?"
print("=== USB (pyusb/libusb) ===")
for d in usb.core.find(find_all=True):
    tag = KNOWN.get((d.idVendor, d.idProduct), "")
    mf, pr = s(d, d.iManufacturer), s(d, d.iProduct)
    hit = tag or any(k in (mf+pr).lower() for k in ("flydigi","apex","xbox","gamepad","controller","wch","nordic"))
    if not hit: continue
    print(f"\n{d.idVendor:04x}:{d.idProduct:04x}  {mf!r} {pr!r}  class={d.bDeviceClass:#04x} {tag}")
    for cfg in d:
        for i in cfg:
            print(f"  if{i.bInterfaceNumber}.{i.bAlternateSetting} class={i.bInterfaceClass:#04x}/{i.bInterfaceSubClass:#04x}/{i.bInterfaceProtocol:#04x}")
            for e in i:
                dr = "IN " if usb.util.endpoint_direction(e.bEndpointAddress) else "OUT"
                ty = ["ctrl","iso","bulk","intr"][usb.util.endpoint_type(e.bmAttributes)]
                print(f"      ep{e.bEndpointAddress & 0x0f:<2} {dr} {ty} max={e.wMaxPacketSize}")
print("\n=== HID (hidapi) ===")
for h in hid.enumerate():
    name = f"{h['manufacturer_string']} {h['product_string']}".lower()
    if (h['vendor_id'],h['product_id']) in KNOWN or any(k in name for k in ("flydigi","apex","xbox","gamepad","controller")):
        print(f"{h['vendor_id']:04x}:{h['product_id']:04x} if={h['interface_number']} usage={h['usage_page']:#06x}/{h['usage']:#06x} {h['manufacturer_string']!r} {h['product_string']!r}\n   {h['path']}")
