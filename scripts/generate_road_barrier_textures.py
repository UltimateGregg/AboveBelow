"""Generate PBR textures for the road-cover concrete barrier (weathered cast concrete).

Standalone numpy + PIL generator. Run from the project root:

    python scripts/generate_road_barrier_textures.py

Writes a tileable colour/normal/roughness/AO set into Assets/materials/environment/:
    road_barrier_concrete_color.png   road_barrier_concrete_normal.png
    road_barrier_concrete_rough.png   road_barrier_concrete_ao.png

The surface is mottled cast-concrete grey with fine aggregate speckle, streaky outdoor
weathering, and scattered chips / pits / hairline cracks. A single shared height field
drives colour, normal, roughness and AO so the lighting depth stays consistent.

Noise: organic fields come from FFT-blurred white noise (circular convolution is
inherently tileable and has NO directional lattice). An earlier sum-of-sines approach
produced a visible diagonal "quilt" once the texture tiled on the model.

Why PIL: s&box's PNG importer cannot decode a single IDAT chunk > ~128 KB (renders the
material flat grey -- the log_cabin bug). PIL splits IDAT into <=64 KB chunks. The script
verifies the chunking at the end.

Normal maps use the OpenGL convention (green = +Y up). If pits look raised instead of
recessed in s&box, flip the green channel (set NORMAL_FLIP_Y = True).
"""

import os
import struct

import numpy as np
from PIL import Image

SIZE = 512
NORMAL_FLIP_Y = False
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "Assets", "materials", "environment"))


# ----------------------------------------------------------------------------- noise
def _fft_noise(size, sigma_x, sigma_y, seed):
    """Tileable organic noise: white noise low-pass filtered in the frequency domain.

    sigma_x / sigma_y are blur radii in pixels (bigger -> larger, smoother blobs).
    Unequal sigmas give anisotropic streaks. Circular convolution keeps it seamless.
    Returns a field normalised to 0..1.
    """
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((size, size))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * ((sigma_x * fx) ** 2 + (sigma_y * fy) ** 2))
    out = np.real(np.fft.ifft2(F * g))
    out -= out.min(); out /= max(out.max(), 1e-6)
    return out


def _fbm(size, seed, sigmas, weights):
    """Multi-scale FFT noise -> natural 1/f cloudiness with no single dominant blob size."""
    acc = np.zeros((size, size)); w = 0.0
    for i, (s, wt) in enumerate(zip(sigmas, weights)):
        acc += wt * _fft_noise(size, s, s, seed + i)
        w += wt
    acc /= max(w, 1e-6)
    acc -= acc.min(); acc /= max(acc.max(), 1e-6)
    return acc


# ----------------------------------------------------------------------------- helpers
def _lerp(c0, c1, t):
    c0 = np.array(c0, float); c1 = np.array(c1, float)
    return c0 * (1.0 - t[..., None]) + c1 * t[..., None]


def _save(arr, name):
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    path = os.path.join(OUT_DIR, name)
    img.save(path, format="PNG", optimize=False)
    return path


def _save_gray(arr01, name):
    a = np.clip(arr01, 0, 1) * 255.0
    return _save(np.dstack([a, a, a]), name)


def _height_to_normal(H, strength, name):
    gx = (np.roll(H, -1, axis=1) - np.roll(H, 1, axis=1)) * 0.5
    gy = (np.roll(H, -1, axis=0) - np.roll(H, 1, axis=0)) * 0.5
    nx = -gx * strength
    ny = -gy * strength * (-1.0 if NORMAL_FLIP_Y else 1.0)
    nz = np.ones_like(H)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    r = (nx / ln * 0.5 + 0.5) * 255.0
    g = (ny / ln * 0.5 + 0.5) * 255.0
    b = (nz / ln * 0.5 + 0.5) * 255.0
    return _save(np.dstack([r, g, b]), name)


def _mask(arr01, lo, hi):
    return np.clip((arr01 - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def _quantile_mask(field, frac, soft=0.02):
    """1 where field is in its top `frac` fraction (soft-edged) -- for sparse specks."""
    thr = float(np.quantile(field, 1.0 - frac))
    return _mask(field, thr, thr + soft)


def _contour(field, k, width):
    """Thin wandering lines following the iso-contours of a smooth field (organic veins)."""
    ph = field * k
    d = np.abs((ph - np.floor(ph)) - 0.5)
    return 1.0 - _mask(d, 0.0, width)


# ----------------------------------------------------------------------------- concrete
def make_concrete():
    S = SIZE

    # cement tone variation: biased to fine/mid scales so there is no ~0.5-1m patch to
    # recur on the ~1m UV tile (large-scale tone repeats into a visible blob rhythm).
    agg = _fbm(S, 201, [30, 14, 7], [0.20, 0.35, 0.45])
    aggregate = _fft_noise(S, 1.6, 1.6, 209)               # fine stone speckle (colour only)

    # pits / blowholes -- sparse small recessed voids
    pits = _quantile_mask(_fft_noise(S, 2.4, 2.4, 204), 0.030, soft=0.015)

    # hairline cracks -- short fragmented veins. Contours of a SMALL-scale field are
    # closely spaced + locally directional, so a sparse break mask leaves short line
    # fragments (large-scale fields give concentric rings that read as blob outlines).
    f1 = _fft_noise(S, 13, 13, 205)
    f2 = _fft_noise(S, 9, 9, 206)
    crack_break = _mask(_fft_noise(S, 9, 9, 207), 0.64, 0.96)
    crack = np.clip(np.maximum(_contour(f1, 12, 0.010), _contour(f2, 16, 0.008)) * crack_break, 0.0, 1.0)

    # vertical outdoor weathering streaks (rain wash / dirt drip): blur wide, keep tall
    streak = _fft_noise(S, 40, 3.5, 210)

    # shared height field -- mostly flat concrete with recessed pits/cracks + fine grain
    H = 0.64 + 0.05 * (aggregate - 0.5)
    H = H - 0.45 * pits - 0.5 * crack
    H = np.clip(H, 0.0, 1.0)

    # ---- colour: warm-neutral concrete greys (tight tonal spread)
    dark = [137, 136, 130]; body = [150, 149, 143]; light = [161, 160, 153]
    col = _lerp(dark, body, _mask(agg, 0.2, 0.55))
    col = _lerp(col, light, _mask(agg, 0.6, 0.95))
    # aggregate stones poking through (colour speckle, both darker + lighter grains)
    col = _lerp(col, [116, 112, 106], _quantile_mask(aggregate, 0.10, 0.02) * 0.5)
    col = _lerp(col, [204, 202, 194], _quantile_mask(1.0 - aggregate, 0.08, 0.02) * 0.55)
    # weathering streaks (dirty grey-green runoff from a damp park) -- main large feature
    col = _lerp(col, [104, 109, 97], _mask(streak, 0.62, 1.0) * 0.5)
    # pits + cracks darken
    col = _lerp(col, [66, 64, 60], np.clip(pits, 0, 1) * 0.8)
    col = col * (1.0 - 0.5 * crack)[..., None]
    _save(col, "road_barrier_concrete_color.png")

    _height_to_normal(H, 1.3, "road_barrier_concrete_normal.png")
    # concrete is rough; pits/cracks rougher, high spots slightly polished by weather
    rough = 0.82 + 0.10 * crack + 0.06 * pits - 0.05 * (agg - 0.5) + 0.03 * streak
    _save_gray(np.clip(rough, 0, 1), "road_barrier_concrete_rough.png")
    ao = 1.0 - 0.6 * pits - 0.6 * crack
    _save_gray(np.clip(ao, 0, 1), "road_barrier_concrete_ao.png")


# ----------------------------------------------------------------------------- verify
def _verify_idat(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: not a PNG"
    off, sizes = 8, []
    while off < len(data):
        (length,) = struct.unpack(">I", data[off:off + 4])
        if data[off + 4:off + 8] == b"IDAT":
            sizes.append(length)
        off += 12 + length
    max_bytes = max(sizes) if sizes else 0
    ok = sizes and max_bytes <= 65536
    print(f"  {os.path.basename(path):36s} IDAT={len(sizes):2d} max={max_bytes:6d} "
          f"-> {'OK' if ok else 'FAIL'}")
    return ok


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    make_concrete()
    names = [
        "road_barrier_concrete_color.png", "road_barrier_concrete_normal.png",
        "road_barrier_concrete_rough.png", "road_barrier_concrete_ao.png",
    ]
    print(f"Wrote {len(names)} textures to {OUT_DIR}")
    if not all(_verify_idat(os.path.join(OUT_DIR, n)) for n in names):
        raise SystemExit("Oversized IDAT chunk; aborting.")
    print("All textures OK (IDAT chunked <=64KB).")


if __name__ == "__main__":
    main()
