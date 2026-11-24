"""Bakes assets/pania_terrain.bin: a square elevation grid around Pania della Croce (Tuscany).

Data: AWS Terrain Tiles (Terrarium), which derive from SRTM/Copernicus and others
(https://registry.opendata.aws/terrain-tiles/). Needs `pillow` and `numpy`.

Layout (little endian): uint16 N, uint16 spacing in metres, then N*N uint16 heights in
decimetres, row-major, north row first.
"""
import io, math, struct, sys, urllib.request
import numpy as np
from PIL import Image

LAT, LON = 44.0350, 10.3235  # approximate summit; refined to the highest cell nearby
Z = 13
HALF_M = 3500  # half width of the window
N = 80
URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'


def tile_xy(lat, lon, z):
    n = 2**z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def fetch(x, y):
    with urllib.request.urlopen(URL.format(z=Z, x=x, y=y)) as r:
        a = np.asarray(Image.open(io.BytesIO(r.read())).convert('RGB'), dtype=np.float64)
    return a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768


def mosaic(lat, lon, half_m):
    mpp = 40075016.686 * math.cos(math.radians(lat)) / (256 * 2**Z)
    cx, cy = tile_xy(lat, lon, Z)
    half_px = half_m / mpp
    x0, x1 = int(math.floor(cx - half_px / 256)), int(math.floor(cx + half_px / 256))
    y0, y1 = int(math.floor(cy - half_px / 256)), int(math.floor(cy + half_px / 256))
    rows = [np.hstack([fetch(x, y) for x in range(x0, x1 + 1)]) for y in range(y0, y1 + 1)]
    return np.vstack(rows), x0, y0, mpp


def sample(img, x0, y0, cx, cy, half_px, n):
    out = np.zeros((n, n))
    for r in range(n):
        for c in range(n):
            px = (cx - x0) * 256 + (c / (n - 1) * 2 - 1) * half_px
            py = (cy - y0) * 256 + (r / (n - 1) * 2 - 1) * half_px
            ix, iy = int(px), int(py)
            fx, fy = px - ix, py - iy
            a, b, d, e = img[iy, ix], img[iy, ix + 1], img[iy + 1, ix], img[iy + 1, ix + 1]
            out[r, c] = (a * (1 - fx) + b * fx) * (1 - fy) + (d * (1 - fx) + e * fx) * fy
    return out


# First pass: find the highest point near the guess so the peak sits in the middle.
img, x0, y0, mpp = mosaic(LAT, LON, 2500)
cx, cy = tile_xy(LAT, LON, Z)
win = int(1500 / mpp)
px, py = int((cx - x0) * 256), int((cy - y0) * 256)
sub = img[py - win:py + win, px - win:px + win]
iy, ix = np.unravel_index(np.argmax(sub), sub.shape)
peak_x = x0 + (px - win + ix) / 256
peak_y = y0 + (py - win + iy) / 256
print('peak elevation near guess: %.0f m' % sub.max(), file=sys.stderr)

# Second pass: centred on the peak.
n_ = 2**Z
lon = peak_x / n_ * 360 - 180
lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * peak_y / n_))))
img, x0, y0, mpp = mosaic(lat, lon, HALF_M + 300)
cx, cy = tile_xy(lat, lon, Z)
grid = sample(img, x0, y0, cx, cy, HALF_M / mpp, N)
spacing = int(round(2 * HALF_M / (N - 1)))
print('peak %.5f, %.5f  min %.0f max %.0f m  spacing %d m' % (lat, lon, grid.min(), grid.max(), spacing), file=sys.stderr)

with open('assets/pania_terrain.bin', 'wb') as f:
    f.write(struct.pack('<HH', N, spacing))
    f.write(np.clip(np.round(grid * 10), 0, 65535).astype('<u2').tobytes())
