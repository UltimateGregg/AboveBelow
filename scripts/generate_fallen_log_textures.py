"""Generate PBR textures for the fallen-log cover set (bark, end-grain, moss).

Standalone numpy + PIL generator. Run from the project root:

    python scripts/generate_fallen_log_textures.py

For each material it writes a colour map plus normal / roughness (and AO for bark)
maps into Assets/materials/environment/. The bark is built as broken vertical
PLATES (furrows cut by intermittent horizontal cracks) rather than continuous
fibres -- continuous fibres read as a "stringy / corduroy" log. A height field
drives colour, normal, roughness and AO so the lighting depth is consistent.

Why PIL: s&box's PNG importer cannot decode a single IDAT chunk > ~128 KB (renders
the material flat grey -- the log_cabin bug). PIL splits IDAT into <=64 KB chunks.
The script verifies the chunking at the end.

Normal maps use the OpenGL convention (green = +Y up). If bark furrows look raised
instead of recessed in s&box, flip the green channel (set NORMAL_FLIP_Y = True).
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
def _periodic_noise(size, freqs, seed):
    """Sum of integer-frequency sines with random phases -> tiles exactly."""
    rng = np.random.default_rng(seed)
    u = np.linspace(0.0, 1.0, size, endpoint=False)
    uu, vv = np.meshgrid(u, u)
    acc = np.zeros((size, size))
    w = 0.0
    for f in freqs:
        amp = 1.0 / f
        for (fx, fy) in ((f, 0), (0, f), (f, f), (f, -f)):
            ph = rng.uniform(0, 2 * np.pi)
            acc += amp * np.sin(2 * np.pi * (fx * uu + fy * vv) + ph)
        w += amp
    acc /= max(w, 1e-6)
    acc -= acc.min(); acc /= max(acc.max(), 1e-6)
    return acc


def _aniso_noise(size, fx_set, fy_set, seed):
    rng = np.random.default_rng(seed)
    u = np.linspace(0.0, 1.0, size, endpoint=False)
    uu, vv = np.meshgrid(u, u)
    acc = np.zeros((size, size)); w = 0.0
    for fx in fx_set:
        for fy in fy_set:
            amp = 1.0 / (1 + fx + fy)
            ph = rng.uniform(0, 2 * np.pi)
            acc += amp * np.sin(2 * np.pi * (fx * uu + fy * vv) + ph)
            w += amp
    acc /= max(w, 1e-6)
    acc -= acc.min(); acc /= max(acc.max(), 1e-6)
    return acc


def _fbm(size, base, octaves, seed):
    acc = np.zeros((size, size)); amp = 1.0; w = 0.0; f = base
    for o in range(octaves):
        acc += amp * _periodic_noise(size, (f,), seed + o)
        w += amp; amp *= 0.5; f *= 2
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


# ----------------------------------------------------------------------------- bark
def make_bark():
    S = SIZE
    u = np.linspace(0.0, 1.0, S, endpoint=False)
    uu, vv = np.meshgrid(u, u)  # uu = around (cols), vv = length (rows)
    # domain warp so cracks wander
    U = uu + 0.05 * (_periodic_noise(S, (3, 6), 101) - 0.5)
    V = vv + 0.05 * (_periodic_noise(S, (3, 6), 102) - 0.5)
    # vertical furrows (narrow deep grooves, run along the length)
    sv = np.abs(np.sin(np.pi * (U * 9 + 0.18 * _periodic_noise(S, (5, 9), 103))))
    groove_v = 1.0 - _mask(sv, 0.0, 0.17)
    # horizontal cracks -- intermittent, break the furrows into plates
    sh = np.abs(np.sin(np.pi * (V * 6 + 0.45 * _periodic_noise(S, (4, 8), 104))))
    hmask = _periodic_noise(S, (5, 11), 105)
    groove_h = (1.0 - _mask(sh, 0.0, 0.10)) * _mask(hmask, 0.45, 0.8)
    crack = np.clip(np.maximum(groove_v, 0.85 * groove_h), 0.0, 1.0)
    # plate-face relief
    detail = 0.6 * _aniso_noise(S, (13, 27, 53), (2, 4, 8), 106) + 0.4 * _fbm(S, 24, 3, 107)
    H = np.clip((1.0 - crack) * (0.5 + 0.5 * detail), 0.0, 1.0)

    # colour
    crackc = [26, 17, 11]; body = [86, 60, 39]; ridge = [150, 123, 95]
    col = _lerp(crackc, body, _mask(H, 0.0, 0.6))
    col = _lerp(col, ridge, _mask(H, 0.62, 1.0))
    var = _periodic_noise(S, (2, 3, 5), 108)
    col = _lerp(col, [122, 66, 42], _mask(var, 0.58, 0.95) * 0.5 * (H > 0.3))   # reddish patches
    lich = _periodic_noise(S, (4, 7, 13), 109)
    col = _lerp(col, [140, 137, 122], _mask(lich, 0.72, 1.0) * 0.55 * (H > 0.45))  # grey lichen
    _save(col, "fallen_log_bark_color.png")

    _height_to_normal(H, 2.4, "fallen_log_bark_normal.png")
    _save_gray(np.clip(0.70 + 0.22 * crack + 0.06 * detail, 0, 1), "fallen_log_bark_rough.png")
    _save_gray(np.clip(1.0 - 0.7 * crack, 0, 1), "fallen_log_bark_ao.png")


# ----------------------------------------------------------------------------- end grain
def make_endgrain():
    S = SIZE
    c = (S - 1) / 2.0
    yy, xx = np.mgrid[0:S, 0:S]
    dx = (xx - c) / c; dy = (yy - c) / c
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    wobble = 0.025 * np.sin(ang * 7) + 0.015 * np.sin(ang * 13 + 0.7)   # gentle, round-ish rings
    ringspace = 17.0 + 2.0 * np.sin(ang * 2.0)
    rings = 0.5 + 0.5 * np.sin((r + wobble) * np.pi * 2.0 * ringspace)
    rings = rings ** 1.5
    grain = 0.12 * _periodic_noise(S, (40, 80), 207)
    H = np.clip((1.0 - rings) * 0.8 + grain + (1.0 - _mask(r, 0.0, 0.9)) * 0.1, 0, 1)

    light = [168, 134, 88]; dark = [104, 76, 47]
    col = _lerp(light, dark, np.clip(rings, 0, 1))
    col = _lerp(col, [126, 74, 50], _mask(1.0 - r, 0.55, 1.0) * 0.5)   # heartwood
    # a few faint radial cracks
    cracks = (np.abs(((ang / np.pi) * 2.5 + 0.5) % 1.0 - 0.5) < 0.010) & (r < 0.8)
    col[cracks] *= 0.6
    col = _lerp(col, [70, 49, 32], _mask(r, 0.9, 1.0))   # bark rim
    _save(col, "fallen_log_endgrain_color.png")

    _height_to_normal(H, 1.6, "fallen_log_endgrain_normal.png")
    _save_gray(np.clip(0.74 + 0.12 * rings, 0, 1), "fallen_log_endgrain_rough.png")


# ----------------------------------------------------------------------------- moss
def make_moss():
    S = SIZE
    base = _periodic_noise(S, (4, 7, 11), 7)
    fine = _periodic_noise(S, (17, 29, 53), 31)
    clump = _periodic_noise(S, (3, 5), 51)
    t = np.clip(0.35 * base + 0.45 * clump + 0.20 * fine, 0, 1)
    col = _lerp([34, 52, 26], [62, 88, 40], _mask(t, 0.0, 0.72))
    col = _lerp(col, [104, 130, 58], _mask(t, 0.65, 1.0))
    col *= (0.85 + 0.25 * fine)[..., None]
    _save(col, "fallen_log_moss_color.png")

    H = np.clip(0.5 * clump + 0.5 * fine, 0, 1)
    _height_to_normal(H, 1.8, "fallen_log_moss_normal.png")
    _save_gray(np.clip(0.90 + 0.06 * fine, 0, 1), "fallen_log_moss_rough.png")


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
    print(f"  {os.path.basename(path):34s} IDAT={len(sizes):2d} max={max_bytes:6d} "
          f"-> {'OK' if ok else 'FAIL'}")
    return ok


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    make_bark(); make_endgrain(); make_moss()
    names = [
        "fallen_log_bark_color.png", "fallen_log_bark_normal.png",
        "fallen_log_bark_rough.png", "fallen_log_bark_ao.png",
        "fallen_log_endgrain_color.png", "fallen_log_endgrain_normal.png",
        "fallen_log_endgrain_rough.png",
        "fallen_log_moss_color.png", "fallen_log_moss_normal.png",
        "fallen_log_moss_rough.png",
    ]
    print(f"Wrote {len(names)} textures to {OUT_DIR}")
    if not all(_verify_idat(os.path.join(OUT_DIR, n)) for n in names):
        raise SystemExit("Oversized IDAT chunk; aborting.")
    print("All textures OK (IDAT chunked <=64KB).")


if __name__ == "__main__":
    main()
