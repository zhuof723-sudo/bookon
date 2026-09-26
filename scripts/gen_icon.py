import zlib, struct, math
W = H = 1024
rows = []
for y in range(H):
    row = bytearray([0])
    for x in range(W):
        # gradient background
        t = y / H
        r = int(40 + 30 * t); g = int(110 + 40 * t); b = int(200 - 20 * t)
        # book shape: two pages
        cx, cy = x - 512, y - 540
        inbook = abs(cx) < 330 and -230 < cy < 250 - abs(cx) * 0.12 and cy > -230 + abs(cx) * 0.12 - 40
        spine = abs(cx) < 10 and -200 < cy < 250
        if inbook:
            r, g, b = 250, 248, 240
            # text lines
            if 40 < abs(cx) < 290 and int((cy + 200) / 45) % 1 == 0 and (cy + 200) % 45 < 10 and -160 < cy < 180:
                r, g, b = 150, 170, 200
        if spine:
            r, g, b = 60, 90, 150
        row += bytes((r, g, b))
    rows.append(bytes(row))
raw = b"".join(rows)
def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open("/var/minis/workspace/bookon/BookOn/Assets.xcassets/AppIcon.appiconset/icon-1024.png", "wb").write(png)
print("ok")
