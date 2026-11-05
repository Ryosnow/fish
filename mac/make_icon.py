#!/usr/bin/env python3
"""生成 App 图标（纯标准库手写 PNG，无第三方依赖）。

画一个橙粉蓝渐变的圆角方块，中间是 18:00 的白色时钟。
用法：python3 make_icon.py /path/to/icon_1024.png
"""
import math
import struct
import sys
import zlib

SIZE = 1024


def write_png(path, w, h, buf):
    raw = b"".join(b"\x00" + bytes(buf[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def clamp01(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def main(out):
    w = h = SIZE
    cx = cy = SIZE / 2.0
    buf = bytearray(w * h * 4)
    # 低饱和雾蓝灰，与界面默认配色一致
    stops = [(110, 138, 165), (157, 179, 195), (126, 143, 165)]
    margin, radius = 40.0, 220.0
    half = (SIZE - 2 * margin) / 2.0

    # 时针（指向 6 点）与分针（指向 12 点）
    hand_h = (cx, cy, cx, cy + 155, 15.0)
    hand_m = (cx, cy, cx, cy - 220, 10.0)

    for y in range(h):
        row = y * w * 4
        for x in range(w):
            fx, fy = x + 0.5, y + 0.5
            t = clamp01((fx + fy) / (2.0 * SIZE))
            seg = t * 2.0
            i = 0 if seg < 1 else 1
            f = seg - i
            a, b = stops[i], stops[i + 1]
            r = a[0] + (b[0] - a[0]) * f
            g = a[1] + (b[1] - a[1]) * f
            bl = a[2] + (b[2] - a[2]) * f

            # 圆角矩形 SDF
            qx = abs(fx - cx) - (half - radius)
            qy = abs(fy - cy) - (half - radius)
            ox, oy = max(qx, 0.0), max(qy, 0.0)
            d = math.hypot(ox, oy) + min(max(qx, qy), 0.0) - radius
            shape = clamp01(0.5 - d)

            dx, dy = fx - cx, fy - cy
            dist = math.hypot(dx, dy)

            # 白色表盘圆环
            ring = clamp01(0.5 - (abs(dist - 285) - 24))
            # 12 个刻度
            ang = math.atan2(dy, dx)
            k = round(ang / (math.pi / 6))
            tick = 1.0 if (abs(ang - k * (math.pi / 6)) < 0.05 and 322 < dist < 344) else 0.0
            # 指针与中心点
            hand = max(
                clamp01(0.5 - (seg_dist(fx, fy, *hand_h[:4]) - hand_h[4])),
                clamp01(0.5 - (seg_dist(fx, fy, *hand_m[:4]) - hand_m[4])),
            )
            dot = clamp01(0.5 - (dist - 24))
            white = max(ring, tick, hand, dot) * 0.96

            r = r * (1 - white) + 255 * white
            g = g * (1 - white) + 255 * white
            bl = bl * (1 - white) + 255 * white

            p = row + x * 4
            buf[p] = int(r)
            buf[p + 1] = int(g)
            buf[p + 2] = int(bl)
            buf[p + 3] = int(shape * 255)

    write_png(out, w, h, buf)
    print("icon written:", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon_1024.png")
