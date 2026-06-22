"""Generate PBR textures for the split-rail park-fence kit (weathered wood + end grain).

Standalone numpy + PIL generator. Run from the project root:

    python scripts/generate_park_fence_textures.py

For each material it writes a colour map plus normal / roughness / AO maps into
Assets/materials/environment/. The wood is sun-greyed, hand-split timber: straight
grain running ALONG the length (V), tight grain lines ACROSS the section (U), with a
few long checking cracks and broad split facets -- not the round corduroy of a bark
log. A single height field drives colour, normal, roughness and AO so the lighting
depth stays consistent.

Why PIL: s&box's PNG importer cannot decode a single IDAT chunk > ~128 KB (renders the
material flat grey -- the log_cabin bug). PIL splits IDAT into <=64 KB chunks. The
script verifies the chunking at the end.

Normal maps use the OpenGL convention (green = +Y up). If grooves look raised instead
of recessed in s&box, flip the green channel (set NORMAL_FLIP_Y = True).

UV convention these tile against (see scripts/build_park_fence.py): U = around the
section (cols), V = along the post/rail length (rows). Grain therefore runs vertically
in the image.
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
    """Anisotropic tiling noise -- different frequency banks per axis."""
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


# ----------------------------------------------------------------------------- wood (posts/rails)
def make_wood():
    """Sun-greyed hand-split timber. Grain runs along V (rows); tight lines across U."""
    S = SIZE
    u = np.linspace(0.0, 1.0, S, endpoint=False)
    uu, vv = np.meshgrid(u, u)   # uu = across section (cols), vv = along length (rows)
    # gentle domain warp so grain wanders a little
    U = uu + 0.035 * (_periodic_noise(S, (3, 7), 211) - 0.5)
    V = vv + 0.020 * (_periodic_noise(S, (2, 5), 212) - 0.5)

    # tight grain lines: many cycles across U, elongated along V
    grain = 0.5 + 0.5 * np.sin(np.pi * (U * 24.0 + 0.55 * _periodic_noise(S, (4, 9), 213)))
    grain = grain ** 1.35
    fine = _aniso_noise(S, (37, 73), (2, 4), 214)          # fine vertical streaks
    facet = _fbm(S, 5, 3, 215)                             # broad split-face blotches

    # long checking cracks running along the length (vertical), intermittent across U
    crackpos = np.abs(np.sin(np.pi * (U * 6.0 + 0.30 * _periodic_noise(S, (3, 6), 216))))
    crackmask = _periodic_noise(S, (2, 4, 7), 217)
    checks = (1.0 - _mask(crackpos, 0.0, 0.05)) * _mask(crackmask, 0.52, 0.86)
    # a couple of short cross-checks where the wood weathered
    xcheck = (1.0 - _mask(np.abs(np.sin(np.pi * (V * 9.0 + 0.4 * _periodic_noise(S, (4, 8), 218)))), 0.0, 0.04)) \
        * _mask(_periodic_noise(S, (5, 11), 219), 0.70, 0.92)
    crack = np.clip(np.maximum(checks, 0.7 * xcheck), 0.0, 1.0)

    H = np.clip(0.45 + 0.30 * (1.0 - grain) * 0.6 + 0.18 * fine + 0.16 * facet - 0.85 * crack, 0.0, 1.0)

    # colour: weathered grey-brown, silvered ridges, dark cracks, warm patches
    crackc = [38, 30, 22]; body = [134, 116, 92]; shade = [92, 76, 56]; silver = [168, 161, 146]
    col = _lerp(crackc, shade, _mask(H, 0.05, 0.45))
    col = _lerp(col, body, _mask(H, 0.40, 0.72))
    col = _lerp(col, silver, _mask(H, 0.74, 1.0))          # sun-bleached high faces
    warm = _periodic_noise(S, (2, 3, 6), 220)
    col = _lerp(col, [120, 84, 56], _mask(warm, 0.60, 0.95) * 0.45 * (H > 0.3))   # warm heart patches
    grey = _periodic_noise(S, (3, 6, 11), 221)
    col = _lerp(col, [142, 140, 128], _mask(grey, 0.74, 1.0) * 0.45 * (H > 0.45))  # grey weathering
    col[crack > 0.55] *= 0.7
    _save(col, "fence_wood_color.png")

    _height_to_normal(H, 2.0, "fence_wood_normal.png")
    _save_gray(np.clip(0.74 + 0.18 * crack + 0.06 * (1.0 - grain), 0, 1), "fence_wood_rough.png")
    _save_gray(np.clip(1.0 - 0.65 * crack, 0, 1), "fence_wood_ao.png")


# ----------------------------------------------------------------------------- end grain (cut ends / post tops)
def make_endgrain():
    """Sawn/split end: growth rings plus radial splits, greyed to match weathered wood."""
    S = SIZE
    c = (S - 1) / 2.0
    yy, xx = np.mgrid[0:S, 0:S]
    dx = (xx - c) / c; dy = (yy - c) / c
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    wobble = 0.030 * np.sin(ang * 6) + 0.018 * np.sin(ang * 11 + 0.6)
    ringspace = 15.0 + 2.0 * np.sin(ang * 2.0)
    rings = 0.5 + 0.5 * np.sin((r + wobble) * np.pi * 2.0 * ringspace)
    rings = rings ** 1.5
    saw = 0.10 * _aniso_noise(S, (60,), (2, 5), 231)          # faint parallel saw marks
    grain = 0.10 * _periodic_noise(S, (40, 80), 232)
    # a few radial splits from drying
    splits = (np.abs(((ang / np.pi) * 2.0 + 0.5) % 1.0 - 0.5) < 0.012) & (r < 0.85)
    H = np.clip((1.0 - rings) * 0.75 + saw + grain + (1.0 - _mask(r, 0.0, 0.9)) * 0.1, 0, 1)
    H[splits] *= 0.35

    light = [150, 130, 100]; dark = [96, 76, 54]
    col = _lerp(light, dark, np.clip(rings, 0, 1))
    col = _lerp(col, [120, 92, 64], _mask(1.0 - r, 0.55, 1.0) * 0.4)     # heartwood
    grey = _periodic_noise(S, (3, 6), 233)
    col = _lerp(col, [150, 146, 134], _mask(grey, 0.70, 1.0) * 0.4)      # weathered grey wash
    col[splits] *= 0.55
    col = _lerp(col, [70, 56, 40], _mask(r, 0.92, 1.0))                  # darker rim
    _save(col, "fence_endgrain_color.png")

    _height_to_normal(H, 1.5, "fence_endgrain_normal.png")
    _save_gray(np.clip(0.78 + 0.12 * rings, 0, 1), "fence_endgrain_rough.png")


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
    print(f"  {os.path.basename(path):32s} IDAT={len(sizes):2d} max={max_bytes:6d} "
          f"-> {'OK' if ok else 'FAIL'}")
    return ok


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    make_wood(); make_endgrain()
    names = [
        "fence_wood_color.png", "fence_wood_normal.png",
        "fence_wood_rough.png", "fence_wood_ao.png",
        "fence_endgrain_color.png", "fence_endgrain_normal.png",
        "fence_endgrain_rough.png",
    ]
    print(f"Wrote {len(names)} textures to {OUT_DIR}")
    if not all(_verify_idat(os.path.join(OUT_DIR, n)) for n in names):
        raise SystemExit("Oversized IDAT chunk; aborting.")
    print("All textures OK (IDAT chunked <=64KB).")


if __name__ == "__main__":
    main()
