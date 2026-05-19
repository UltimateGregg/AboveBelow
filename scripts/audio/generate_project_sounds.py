#!/usr/bin/env python3
"""
Deterministic project sound generator.

This is not intended to compete with stock S&Box recordings. It imports known
stock WAV sources into local Assets/sounds wrappers when possible, then
generates only the project-specific cues that need to exist locally. Gameplay
code, prefabs, and scenes should reference local .sound wrappers, not direct
mounted package SoundEvents.
"""

from __future__ import annotations

import argparse
import math
import random
import re
import shutil
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 48_000
TAU = math.tau


def envelope(t: float, start: float, duration: float, attack: float = 0.006, release: float = 0.05, curve: float = 2.0) -> float:
    local = t - start
    if local < 0.0 or local >= duration:
        return 0.0
    if attack > 0 and local < attack:
        return local / attack
    remaining = duration - local
    if release > 0 and remaining < release:
        return max(0.0, remaining / release)
    body = max(0.0, 1.0 - (local / max(duration, 0.0001)))
    return body ** curve


def add_tone(buf: list[float], start: float, duration: float, freq_a: float, freq_b: float | None, amp: float,
             attack: float = 0.004, release: float = 0.04, curve: float = 2.0, harmonics: tuple[float, ...] = ()) -> None:
    start_i = max(0, int(start * SAMPLE_RATE))
    end_i = min(len(buf), int((start + duration) * SAMPLE_RATE))
    phase = 0.0
    for i in range(start_i, end_i):
        t = i / SAMPLE_RATE
        u = (t - start) / max(duration, 0.0001)
        freq = freq_a + ((freq_b if freq_b is not None else freq_a) - freq_a) * u
        phase += TAU * freq / SAMPLE_RATE
        value = math.sin(phase)
        for idx, h_amp in enumerate(harmonics, start=2):
            value += h_amp * math.sin(phase * idx)
        buf[i] += value * amp * envelope(t, start, duration, attack, release, curve)


def add_filtered_noise(buf: list[float], start: float, duration: float, amp: float, seed: int,
                       lowpass: float = 0.12, highpass: float = 0.0, attack: float = 0.002,
                       release: float = 0.04, curve: float = 2.0) -> None:
    rng = random.Random(seed)
    start_i = max(0, int(start * SAMPLE_RATE))
    end_i = min(len(buf), int((start + duration) * SAMPLE_RATE))
    low = 0.0
    prev_low = 0.0
    for i in range(start_i, end_i):
        white = rng.uniform(-1.0, 1.0)
        low += lowpass * (white - low)
        value = low
        if highpass > 0:
            high = white - prev_low
            prev_low += highpass * (white - prev_low)
            value = high
        t = i / SAMPLE_RATE
        buf[i] += value * amp * envelope(t, start, duration, attack, release, curve)


def add_wind_whoosh(buf: list[float], start: float, duration: float, amp: float, seed: int,
                    upper_lowpass: float = 0.045, lower_lowpass: float = 0.006,
                    attack: float = 0.7, release: float = 0.9) -> None:
    rng = random.Random(seed)
    start_i = max(0, int(start * SAMPLE_RATE))
    end_i = min(len(buf), int((start + duration) * SAMPLE_RATE))
    upper = 0.0
    lower = 0.0
    for i in range(start_i, end_i):
        white = rng.uniform(-1.0, 1.0)
        upper += upper_lowpass * (white - upper)
        lower += lower_lowpass * (white - lower)
        t = i / SAMPLE_RATE
        gust = 0.72 + 0.28 * math.sin(TAU * (t - start) / max(duration, 0.001))
        buf[i] += (upper - lower) * amp * gust * envelope(t, start, duration, attack, release, curve=0.55)


def add_click(buf: list[float], at: float, amp: float, seed: int, tone: float = 2800.0) -> None:
    add_filtered_noise(buf, at, 0.018, amp, seed, lowpass=0.45, highpass=0.18, release=0.014, curve=4.0)
    add_tone(buf, at, 0.035, tone, tone * 0.65, amp * 0.22, attack=0.001, release=0.025, curve=3.5)


def add_debris(buf: list[float], count: int, start: float, end: float, amp: float, seed: int) -> None:
    rng = random.Random(seed)
    for n in range(count):
        at = rng.uniform(start, end)
        add_click(buf, at, amp * rng.uniform(0.35, 1.0), seed + n * 37, tone=rng.uniform(900, 4200))


def render(duration: float, builder, peak: float = 0.82) -> list[float]:
    buf = [0.0] * int(duration * SAMPLE_RATE)
    builder(buf)
    return finish(buf, peak=peak)


def finish(buf: list[float], peak: float = 0.92) -> list[float]:
    # Gentle saturation before normalization keeps transients from turning into
    # square clicks while still sounding direct in-game.
    for i, sample in enumerate(buf):
        buf[i] = math.tanh(sample * 1.2) / math.tanh(1.2)
    max_amp = max((abs(x) for x in buf), default=0.0)
    if max_amp > 0.00001:
        gain = peak / max_amp
        for i, sample in enumerate(buf):
            buf[i] = max(-0.98, min(0.98, sample * gain))
    fade_len = min(96, len(buf) // 8)
    for i in range(fade_len):
        fade = i / fade_len
        buf[i] *= fade
        buf[-i - 1] *= fade
    return buf


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = bytearray()
    for sample in samples:
        value = int(max(-1.0, min(1.0, sample)) * 32767)
        pcm.extend(struct.pack("<h", value))
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(bytes(pcm))


def rifle_world() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.090, 92, 47, 0.55, release=0.06, curve=2.8, harmonics=(0.25,))
        add_filtered_noise(b, 0.001, 0.045, 0.62, 1001, lowpass=0.30, highpass=0.28, release=0.035, curve=3.2)
        add_filtered_noise(b, 0.025, 0.200, 0.30, 1002, lowpass=0.08, highpass=0.05, release=0.14, curve=2.4)
        add_tone(b, 0.035, 0.180, 680, 210, 0.11, release=0.14, curve=2.2)
        add_filtered_noise(b, 0.090, 0.090, 0.08, 1003, lowpass=0.10, highpass=0.04, release=0.06, curve=2.0)
    return render(0.28, build, peak=0.88)


def rifle_first_person() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.070, 120, 60, 0.50, release=0.055, curve=2.5)
        add_filtered_noise(b, 0.001, 0.034, 0.70, 1101, lowpass=0.38, highpass=0.35, release=0.026, curve=3.7)
        add_click(b, 0.052, 0.20, 1102, tone=1900)
        add_filtered_noise(b, 0.060, 0.140, 0.16, 1103, lowpass=0.08, highpass=0.05, release=0.09, curve=2.5)
    return render(0.22, build, peak=0.72)


def shotgun_fire() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.170, 76, 38, 0.72, release=0.13, curve=2.2, harmonics=(0.18,))
        add_filtered_noise(b, 0.002, 0.070, 0.64, 1201, lowpass=0.27, highpass=0.24, release=0.06, curve=3.0)
        add_filtered_noise(b, 0.045, 0.420, 0.34, 1202, lowpass=0.06, highpass=0.03, release=0.26, curve=1.8)
        add_debris(b, 7, 0.075, 0.260, 0.08, 1203)
    return render(0.58, build, peak=0.88)


def reload_full() -> list[float]:
    def build(b):
        add_click(b, 0.025, 0.25, 1301, tone=1600)
        add_filtered_noise(b, 0.080, 0.120, 0.18, 1302, lowpass=0.12, highpass=0.06, release=0.08, curve=2.2)
        add_click(b, 0.250, 0.34, 1303, tone=950)
        add_click(b, 0.415, 0.24, 1304, tone=2100)
    return render(0.62, build, peak=0.62)


def mag_drop() -> list[float]:
    def build(b):
        add_click(b, 0.018, 0.32, 1401, tone=820)
        add_tone(b, 0.028, 0.180, 430, 210, 0.16, release=0.12, curve=2.5)
        add_debris(b, 3, 0.090, 0.210, 0.08, 1402)
    return render(0.30, build, peak=0.56)


def mag_insert() -> list[float]:
    def build(b):
        add_filtered_noise(b, 0.000, 0.080, 0.17, 1501, lowpass=0.16, highpass=0.08, release=0.05, curve=2.0)
        add_click(b, 0.095, 0.42, 1502, tone=1450)
        add_tone(b, 0.105, 0.085, 620, 320, 0.13, release=0.060, curve=2.6)
    return render(0.26, build, peak=0.60)


def bolt_rack() -> list[float]:
    def build(b):
        add_filtered_noise(b, 0.000, 0.090, 0.22, 1601, lowpass=0.18, highpass=0.09, release=0.04, curve=1.8)
        add_click(b, 0.120, 0.34, 1602, tone=1850)
        add_filtered_noise(b, 0.155, 0.100, 0.15, 1603, lowpass=0.10, highpass=0.06, release=0.06, curve=2.0)
    return render(0.32, build, peak=0.58)


def empty_click() -> list[float]:
    def build(b):
        add_click(b, 0.012, 0.42, 1701, tone=2600)
        add_tone(b, 0.020, 0.055, 1250, 760, 0.12, release=0.040, curve=3.0)
    return render(0.12, build, peak=0.48)


def bullet_whip() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.135, 3100, 520, 0.46, attack=0.001, release=0.065, curve=1.4, harmonics=(0.12,))
        add_filtered_noise(b, 0.000, 0.115, 0.18, 1801, lowpass=0.25, highpass=0.35, release=0.050, curve=1.7)
        add_tone(b, 0.060, 0.100, 620, 350, 0.10, release=0.070, curve=2.5)
    return render(0.22, build, peak=0.60)


def drone_beam() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.180, 920, 1320, 0.44, attack=0.002, release=0.055, curve=1.7, harmonics=(0.22, 0.08))
        add_filtered_noise(b, 0.002, 0.060, 0.18, 1901, lowpass=0.18, highpass=0.28, release=0.035, curve=2.5)
        add_tone(b, 0.035, 0.125, 210, 120, 0.16, release=0.070, curve=2.4)
    return render(0.22, build, peak=0.62)


def drone_hum() -> list[float]:
    duration = 4.0
    def build(b):
        for i in range(len(b)):
            t = i / SAMPLE_RATE
            lfo = 0.75 + 0.25 * math.sin(TAU * 5.0 * t)
            wobble = math.sin(TAU * 0.55 * t) * 8.0
            b[i] += math.sin(TAU * (92 + wobble) * t) * 0.20 * lfo
            b[i] += math.sin(TAU * (184 + wobble * 1.7) * t) * 0.10 * lfo
            b[i] += math.sin(TAU * (368 + wobble * 2.2) * t) * 0.045 * lfo
        add_filtered_noise(b, 0.0, duration, 0.035, 2001, lowpass=0.025, highpass=0.0, attack=0.01, release=0.01, curve=0.15)
    return render(duration, build, peak=0.34)


def jammer_loop() -> list[float]:
    duration = 1.5
    def build(b):
        for i in range(len(b)):
            t = i / SAMPLE_RATE
            gate = 0.58 + 0.42 * (0.5 + 0.5 * math.sin(TAU * 8 * t))
            b[i] += math.sin(TAU * 120 * t) * 0.15 * gate
            b[i] += math.sin(TAU * 240 * t + math.sin(TAU * 3 * t) * 0.65) * 0.10 * gate
            b[i] += math.sin(TAU * 960 * t) * 0.025 * gate
        add_filtered_noise(b, 0.0, duration, 0.045, 2101, lowpass=0.035, highpass=0.12, attack=0.01, release=0.01, curve=0.2)
    return render(duration, build, peak=0.38)


def grenade_throw() -> list[float]:
    def build(b):
        add_filtered_noise(b, 0.000, 0.160, 0.22, 2201, lowpass=0.11, highpass=0.08, release=0.070, curve=1.8)
        add_click(b, 0.045, 0.22, 2202, tone=1900)
        add_tone(b, 0.105, 0.150, 360, 180, 0.10, release=0.10, curve=2.4)
    return render(0.30, build, peak=0.54)


def grenade_explosion() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.280, 56, 26, 0.85, attack=0.002, release=0.22, curve=1.8, harmonics=(0.12,))
        add_filtered_noise(b, 0.002, 0.075, 0.70, 2301, lowpass=0.24, highpass=0.28, release=0.060, curve=2.6)
        add_filtered_noise(b, 0.055, 0.820, 0.44, 2302, lowpass=0.035, highpass=0.00, release=0.52, curve=1.5)
        add_debris(b, 14, 0.070, 0.620, 0.09, 2303)
    return render(1.05, build, peak=0.88)


def impact_concrete() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.070, 150, 80, 0.28, release=0.045, curve=2.6)
        add_filtered_noise(b, 0.001, 0.060, 0.34, 2401, lowpass=0.12, highpass=0.16, release=0.050, curve=2.5)
        add_debris(b, 5, 0.025, 0.150, 0.06, 2402)
    return render(0.22, build, peak=0.58)


def impact_metal() -> list[float]:
    def build(b):
        add_click(b, 0.000, 0.40, 2501, tone=2400)
        add_tone(b, 0.012, 0.260, 820, 805, 0.18, attack=0.001, release=0.190, curve=1.9, harmonics=(0.16,))
        add_tone(b, 0.014, 0.220, 1550, 1500, 0.09, attack=0.001, release=0.170, curve=2.0)
    return render(0.30, build, peak=0.56)


def impact_flesh() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.110, 118, 55, 0.34, release=0.080, curve=2.4)
        add_filtered_noise(b, 0.003, 0.080, 0.18, 2601, lowpass=0.08, highpass=0.02, release=0.060, curve=2.2)
    return render(0.20, build, peak=0.50)


def footstep(seed: int) -> list[float]:
    rng = random.Random(seed)
    def build(b):
        add_tone(b, 0.000, 0.075, rng.uniform(82, 105), rng.uniform(46, 60), 0.16, release=0.050, curve=2.2)
        add_filtered_noise(b, 0.004, 0.085, 0.075, seed + 1, lowpass=0.032, highpass=0.010, release=0.060, curve=1.9)
        add_tone(b, 0.024, 0.060, rng.uniform(155, 210), rng.uniform(120, 150), 0.045, release=0.040, curve=2.4)
    return render(0.18, build, peak=0.24)


def jump_grunt() -> list[float]:
    def build(b):
        add_filtered_noise(b, 0.000, 0.130, 0.16, 2801, lowpass=0.07, highpass=0.04, release=0.070, curve=1.8)
        add_tone(b, 0.000, 0.135, 180, 92, 0.16, release=0.090, curve=2.6)
    return render(0.22, build, peak=0.38)


def land_thud() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.130, 86, 38, 0.48, release=0.095, curve=2.1)
        add_filtered_noise(b, 0.004, 0.150, 0.22, 2901, lowpass=0.075, highpass=0.035, release=0.110, curve=2.0)
        add_debris(b, 5, 0.030, 0.210, 0.040, 2902)
    return render(0.32, build, peak=0.54)


def hitmarker(kill: bool = False) -> list[float]:
    def build(b):
        add_tone(b, 0.000, 0.070, 1500 if not kill else 1260, 1500 if not kill else 1260, 0.25, release=0.040, curve=2.8)
        add_tone(b, 0.018 if kill else 0.0, 0.100 if kill else 0.055, 2200 if not kill else 1890, None, 0.18, release=0.050, curve=2.6)
        if kill:
            add_tone(b, 0.075, 0.130, 630, 940, 0.18, release=0.080, curve=1.7)
    return render(0.18 if kill else 0.10, build, peak=0.42 if not kill else 0.48)


def round_swell() -> list[float]:
    def build(b):
        add_tone(b, 0.000, 1.200, 145, 210, 0.18, attack=0.18, release=0.25, curve=0.6, harmonics=(0.15,))
        add_tone(b, 0.300, 0.800, 520, 780, 0.11, attack=0.16, release=0.25, curve=0.8)
        add_click(b, 1.020, 0.22, 3101, tone=1700)
    return render(1.25, build, peak=0.46)


def ambient_battlefield() -> list[float]:
    duration = 4.0
    def build(b):
        add_filtered_noise(b, 0.0, duration, 0.085, 3201, lowpass=0.018, highpass=0.0, attack=0.6, release=0.6, curve=0.25)
        add_tone(b, 0.0, duration, 72, 70, 0.035, attack=0.5, release=0.5, curve=0.2)
        for at, amp in [(0.7, 0.035), (1.9, 0.025), (3.1, 0.030)]:
            add_filtered_noise(b, at, 0.45, amp, 3202 + int(at * 10), lowpass=0.05, highpass=0.08, attack=0.08, release=0.25, curve=1.0)
    return render(duration, build, peak=0.28)


def ambient_tree_rustle() -> list[float]:
    duration = 10.0

    def build(b):
        add_filtered_noise(b, 0.0, duration, 0.030, 3301, lowpass=0.025, highpass=0.015, attack=0.8, release=0.8, curve=0.35)
        for at, length, amp, seed in [
            (0.45, 0.85, 0.060, 3311),
            (1.80, 1.10, 0.050, 3312),
            (3.15, 0.70, 0.042, 3313),
            (4.70, 1.35, 0.058, 3314),
            (6.55, 0.90, 0.046, 3315),
            (8.20, 1.20, 0.052, 3316),
        ]:
            add_filtered_noise(b, at, length, amp, seed, lowpass=0.11, highpass=0.06, attack=0.12, release=0.35, curve=1.4)
        add_debris(b, 18, 0.3, duration - 0.4, 0.010, 3330)

    return render(duration, build, peak=0.20)


def ambient_light_wind() -> list[float]:
    duration = 16.0

    def build(b):
        for at, length, amp, seed in [
            (0.00, 5.40, 0.030, 3351),
            (4.20, 4.70, 0.025, 3352),
            (8.00, 5.80, 0.028, 3353),
            (12.10, 3.70, 0.022, 3354),
        ]:
            add_wind_whoosh(b, at, length, amp, seed)

    return render(duration, build, peak=0.18)


def add_modulated_bird_tone(buf: list[float], start: float, duration: float, freq_a: float, freq_b: float,
                            amp: float, seed: int, vibrato_depth: float = 35.0, vibrato_rate: float = 18.0,
                            attack: float = 0.006, release: float = 0.045, curve: float = 1.35,
                            harmonics: tuple[float, ...] = (0.18, 0.06)) -> None:
    rng = random.Random(seed)
    start_i = max(0, int(start * SAMPLE_RATE))
    end_i = min(len(buf), int((start + duration) * SAMPLE_RATE))
    phase = rng.uniform(0.0, TAU)
    vibrato_phase = rng.uniform(0.0, TAU)
    shimmer_phase = rng.uniform(0.0, TAU)
    shimmer_rate = vibrato_rate * rng.uniform(1.8, 2.6)
    for i in range(start_i, end_i):
        t = i / SAMPLE_RATE
        local = t - start
        u = local / max(duration, 0.0001)
        bend = math.sin(TAU * vibrato_rate * local + vibrato_phase) * vibrato_depth
        shimmer = math.sin(TAU * shimmer_rate * local + shimmer_phase) * vibrato_depth * 0.22
        freq = freq_a + (freq_b - freq_a) * u + bend + shimmer
        phase += TAU * max(120.0, freq) / SAMPLE_RATE
        value = math.sin(phase)
        for idx, h_amp in enumerate(harmonics, start=2):
            value += h_amp * math.sin(phase * idx + idx * 0.37)
        buf[i] += value * amp * envelope(t, start, duration, attack, release, curve)


def add_bird_note(buf: list[float], start: float, duration: float, freq_a: float, freq_b: float,
                  amp: float, seed: int, distant: bool = False) -> None:
    add_modulated_bird_tone(
        buf,
        start,
        duration,
        freq_a,
        freq_b,
        amp,
        seed,
        vibrato_depth=22.0 if distant else 42.0,
        vibrato_rate=12.0 if distant else 22.0,
        attack=0.010 if distant else 0.004,
        release=0.070 if distant else 0.040,
        curve=0.95 if distant else 1.45,
        harmonics=(0.10, 0.025) if distant else (0.20, 0.07),
    )
    add_filtered_noise(
        buf,
        start,
        duration * 0.85,
        amp * (0.006 if distant else 0.010),
        seed + 911,
        lowpass=0.10 if distant else 0.16,
        highpass=0.05,
        attack=0.004,
        release=0.030,
        curve=2.0,
    )
    if distant:
        add_modulated_bird_tone(
            buf,
            start + 0.055,
            duration * 0.95,
            freq_a * 0.985,
            freq_b * 0.985,
            amp * 0.13,
            seed + 1201,
            vibrato_depth=10.0,
            vibrato_rate=9.0,
            attack=0.015,
            release=0.095,
            curve=0.9,
            harmonics=(0.04,),
        )


def add_songbird_phrase(buf: list[float], start: float, base_freq: float, amp: float,
                        seed: int, style: str, distant: bool = False) -> None:
    rng = random.Random(seed)
    at = start

    if style == "trill":
        count = rng.randint(8, 13)
        for n in range(count):
            length = rng.uniform(0.025, 0.045)
            freq = base_freq * rng.uniform(0.92, 1.12)
            sweep = rng.uniform(-0.10, 0.16)
            add_bird_note(buf, at, length, freq, freq * (1.0 + sweep), amp * rng.uniform(0.52, 0.82), seed + n * 37, distant)
            at += rng.uniform(0.036, 0.058)
        return

    if style == "whistle":
        count = rng.randint(3, 5)
        for n in range(count):
            length = rng.uniform(0.070, 0.140)
            step = [0.0, 0.17, -0.10, 0.23, -0.18][n % 5]
            freq = base_freq * (1.0 + step + rng.uniform(-0.035, 0.035))
            add_bird_note(buf, at, length, freq, freq * rng.uniform(0.96, 1.08), amp * rng.uniform(0.70, 1.0), seed + n * 41, distant)
            at += length + rng.uniform(0.060, 0.130)
        return

    if style == "chip":
        count = rng.randint(4, 7)
        for n in range(count):
            length = rng.uniform(0.030, 0.065)
            freq = base_freq * rng.uniform(0.78, 1.18)
            add_bird_note(buf, at, length, freq, freq * rng.uniform(1.08, 1.32), amp * rng.uniform(0.62, 1.0), seed + n * 43, distant)
            at += rng.uniform(0.080, 0.180)
        return

    count = rng.randint(5, 9)
    for n in range(count):
        length = rng.uniform(0.040, 0.090)
        freq = base_freq * rng.uniform(0.82, 1.20)
        sweep = rng.choice((-0.22, -0.12, 0.10, 0.18, 0.26))
        add_bird_note(buf, at, length, freq, freq * (1.0 + sweep), amp * rng.uniform(0.55, 0.95), seed + n * 47, distant)
        at += length + rng.uniform(0.025, 0.095)


def add_crow_caw(buf: list[float], start: float, amp: float, seed: int) -> None:
    rng = random.Random(seed)
    at = start
    for n in range(rng.randint(2, 4)):
        length = rng.uniform(0.22, 0.44)
        freq = rng.uniform(420, 610)
        add_modulated_bird_tone(
            buf,
            at,
            length,
            freq,
            freq * rng.uniform(0.72, 0.92),
            amp * rng.uniform(0.75, 1.0),
            seed + n * 53,
            vibrato_depth=55.0,
            vibrato_rate=rng.uniform(6.0, 10.0),
            attack=0.025,
            release=0.150,
            curve=0.65,
            harmonics=(0.38, 0.18, 0.08),
        )
        add_filtered_noise(buf, at + 0.015, length * 0.80, amp * 0.12, seed + n * 59, lowpass=0.050, highpass=0.018, attack=0.020, release=0.130, curve=0.8)
        add_modulated_bird_tone(
            buf,
            at + 0.090,
            length * 0.85,
            freq * 0.96,
            freq * 0.76,
            amp * 0.16,
            seed + n * 61,
            vibrato_depth=22.0,
            vibrato_rate=5.0,
            attack=0.030,
            release=0.190,
            curve=0.7,
            harmonics=(0.16,),
        )
        at += length + rng.uniform(0.20, 0.48)


def ambient_birds_chirping() -> list[float]:
    duration = 32.0

    def build(b):
        phrases = [
            (1.10, 3150, 0.044, 3411, "whistle"),
            (3.85, 4680, 0.034, 3412, "trill"),
            (6.70, 3860, 0.036, 3413, "warble"),
            (10.20, 5220, 0.030, 3414, "chip"),
            (13.60, 2880, 0.040, 3415, "whistle"),
            (17.45, 4420, 0.032, 3416, "warble"),
            (21.30, 4960, 0.029, 3417, "trill"),
            (25.55, 3600, 0.035, 3418, "chip"),
            (29.10, 4200, 0.026, 3419, "warble"),
        ]
        for start, freq, amp, seed, style in phrases:
            add_songbird_phrase(b, start, freq, amp, seed, style)

    return render(duration, build, peak=0.20)


def ambient_birds_canopy_far() -> list[float]:
    duration = 36.0

    def build(b):
        phrases = [
            (0.90, 2500, 0.020, 3511, "whistle"),
            (3.60, 3300, 0.018, 3512, "warble"),
            (5.85, 4150, 0.015, 3513, "trill"),
            (9.40, 2800, 0.019, 3514, "chip"),
            (12.70, 3650, 0.016, 3515, "warble"),
            (15.20, 2350, 0.019, 3516, "whistle"),
            (19.10, 4450, 0.014, 3517, "trill"),
            (23.35, 3100, 0.017, 3518, "chip"),
            (27.80, 3950, 0.015, 3519, "warble"),
            (32.10, 2600, 0.017, 3520, "whistle"),
        ]
        for start, freq, amp, seed, style in phrases:
            add_songbird_phrase(b, start, freq, amp, seed, style, distant=True)

    return render(duration, build, peak=0.14)


def ambient_crows_distant() -> list[float]:
    duration = 44.0

    def build(b):
        for start, amp, seed in [
            (4.40, 0.038, 3611),
            (18.70, 0.031, 3612),
            (34.20, 0.035, 3613),
        ]:
            add_crow_caw(b, start, amp, seed)

    return render(duration, build, peak=0.16)


SOUNDS = {
    "ambient_battlefield.wav": ambient_battlefield,
    "ambient_birds_canopy_far.wav": ambient_birds_canopy_far,
    "ambient_light_wind.wav": ambient_light_wind,
    "ambient_crows_distant.wav": ambient_crows_distant,
    "ambient_tree_rustle.wav": ambient_tree_rustle,
    "ambient_birds_chirping.wav": ambient_birds_chirping,
    "assault_rifle_fire.wav": rifle_world,
    "assault_rifle_reload.wav": reload_full,
    "bolt_rack.wav": bolt_rack,
    "bullet_whip.wav": bullet_whip,
    "drone_beam.wav": drone_beam,
    "drone_hum.wav": drone_hum,
    "empty_click.wav": empty_click,
    "footstep_0.wav": lambda: footstep(2701),
    "footstep_1.wav": lambda: footstep(2702),
    "footstep_2.wav": lambda: footstep(2703),
    "footstep_3.wav": lambda: footstep(2704),
    "grenade_explosion.wav": grenade_explosion,
    "grenade_throw.wav": grenade_throw,
    "impact_concrete.wav": impact_concrete,
    "impact_flesh.wav": impact_flesh,
    "impact_metal.wav": impact_metal,
    "jammer_loop.wav": jammer_loop,
    "jump_grunt.wav": jump_grunt,
    "land_thud.wav": land_thud,
    "m4_fire_fp.wav": rifle_first_person,
    "mag_drop.wav": mag_drop,
    "mag_insert.wav": mag_insert,
    "round_start_swell.wav": round_swell,
    "shotgun_fire.wav": shotgun_fire,
    "ui_hitmarker.wav": lambda: hitmarker(False),
    "ui_hitmarker_kill.wav": lambda: hitmarker(True),
}

STOCK_WAVS = {
    # Real editor recordings copied into local wrappers. These are source WAVs,
    # not direct mounted .sound references, because this project does not load
    # cached package SoundEvents by bare path at runtime.
    "assault_rifle_fire.wav": ["weapons/ar15/sounds/ar15_fire.*.wav"],
    "m4_fire_fp.wav": ["weapons/ar15/sounds/ar15_fire_suppressed.*.wav", "weapons/ar15/sounds/ar15_fire.*.wav"],
    "assault_rifle_reload.wav": ["weapons/ar15/sounds/ar15_magin.*.wav"],
    "mag_drop.wav": ["weapons/ar15/sounds/ar15_magout.*.wav"],
    "mag_insert.wav": ["weapons/ar15/sounds/ar15_magin.*.wav"],
    "bolt_rack.wav": ["weapons/ar15/sounds/ar15_boltpull.*.wav"],
    "empty_click.wav": ["sounds/swb/clip/swb_rifle_empty.*.wav"],
    "drone_hum.wav": ["killstreaks/sentrygun/sounds/spinningloop.*.wav"],
    "grenade_explosion.wav": ["killstreaks/predatormissile/sounds/missile_explode.*.wav"],
    "impact_concrete.wav": ["sounds/hit_concrete.*.wav", "sounds/bullet_impact.*.wav"],
    "impact_metal.wav": ["sounds/bullet_impact.*.wav"],
    "round_start_swell.wav": ["sounds/gameplay/events/event_1.*.wav"],
    "shotgun_fire.wav": ["weapons/benelli_m4/sounds/benelli_m4_fire.*.wav"],
    "ui_hitmarker.wav": [
        "sounds/swb/hit/swb_hitmarker.*.wav",
        "sounds/swb/hit/hitmarker.*.wav",
        "sounds/ui/sf_hitmarker.*.wav",
    ],
    "ui_hitmarker_kill.wav": ["sounds/ui/sf_hitmarker.*.wav", "sounds/swb/hit/hitmarker.*.wav"],
}

STOCK_AUDIO_FILES = {}


def find_sbox_asset_roots(project_root: Path) -> list[Path]:
    roots: list[Path] = []
    for candidate in (
        Path("D:/SteamLibrary/steamapps/common/sbox/download/assets"),
        Path("C:/Program Files (x86)/Steam/steamapps/common/sbox/download/assets"),
        Path("C:/Program Files/Steam/steamapps/common/sbox/download/assets"),
    ):
        if candidate.exists() and candidate not in roots:
            roots.append(candidate)

    project_file = project_root / "Code" / "dronevsplayers.csproj"
    if project_file.exists():
        text = project_file.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r"[A-Z]:[/\\][^\"<>|]*?steamapps[/\\]common[/\\]sbox", text, flags=re.I):
            candidate = Path(match.group(0).replace("\\", "/")) / "download" / "assets"
            if candidate.exists() and candidate not in roots:
                roots.append(candidate)

    return roots


def convert_float_wav_to_pcm16(source: Path, output_path: Path) -> bool:
    data = source.read_bytes()
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return False

    fmt = None
    audio = None
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset : offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        if chunk_end > len(data):
            return False
        if chunk_id == b"fmt ":
            fmt = data[chunk_start:chunk_end]
        elif chunk_id == b"data":
            audio = data[chunk_start:chunk_end]
        offset = chunk_end + (chunk_size & 1)

    if fmt is None or audio is None or len(fmt) < 16:
        return False

    format_tag, channels, sample_rate, _byte_rate, block_align, bits_per_sample = struct.unpack_from("<HHIIHH", fmt, 0)
    if format_tag != 3 or bits_per_sample not in (32, 64) or channels <= 0 or sample_rate <= 0 or block_align <= 0:
        return False

    sample_size = bits_per_sample // 8
    sample_count = len(audio) // sample_size
    if sample_count == 0:
        return False

    if bits_per_sample == 32:
        values = struct.unpack("<" + "f" * sample_count, audio[: sample_count * sample_size])
    else:
        values = struct.unpack("<" + "d" * sample_count, audio[: sample_count * sample_size])

    pcm = bytearray()
    for value in values:
        if not math.isfinite(value):
            value = 0.0
        value = max(-1.0, min(1.0, value))
        pcm.extend(struct.pack("<h", int(value * 32767.0)))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_path), "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(bytes(pcm))

    return True


def copy_stock_wav(project_root: Path, output_path: Path, name: str) -> bool:
    patterns = STOCK_WAVS.get(name)
    if not patterns:
        return False

    for asset_root in find_sbox_asset_roots(project_root):
        for pattern in patterns:
            matches = sorted(asset_root.glob(pattern))
            if not matches:
                continue
            output_path.parent.mkdir(parents=True, exist_ok=True)
            if convert_float_wav_to_pcm16(matches[0], output_path):
                action = "converted stock"
            else:
                shutil.copyfile(matches[0], output_path)
                action = "copied stock"
            print(f"{action} {matches[0].relative_to(asset_root).as_posix()} -> Assets/sounds/{name}")
            return True

    return False


def copy_stock_audio(project_root: Path, output_path: Path, name: str) -> bool:
    patterns = STOCK_AUDIO_FILES.get(name)
    if not patterns:
        return False

    for asset_root in find_sbox_asset_roots(project_root):
        for pattern in patterns:
            matches = sorted(asset_root.glob(pattern))
            if not matches:
                continue
            output_path.parent.mkdir(parents=True, exist_ok=True)
            if matches[0].suffix.lower() == ".wav" and convert_float_wav_to_pcm16(matches[0], output_path):
                action = "converted stock"
            else:
                shutil.copyfile(matches[0], output_path)
                action = "copied stock"
            print(f"{action} {matches[0].relative_to(asset_root).as_posix()} -> Assets/sounds/{name}")
            return True

    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Project root")
    parser.add_argument("--only", nargs="*", default=[], help="Optional wav file names to regenerate")
    parser.add_argument("--synthetic-only", action="store_true", help="Ignore stock editor WAVs and synthesize every file")
    args = parser.parse_args()

    project_root = Path(args.root).resolve()
    sound_dir = project_root / "Assets" / "sounds"
    requested = set(args.only)
    if not args.synthetic_only:
        for name in STOCK_AUDIO_FILES:
            if requested and name not in requested:
                continue
            copy_stock_audio(project_root, sound_dir / name, name)

    for name, builder in SOUNDS.items():
        if requested and name not in requested:
            continue
        output_path = sound_dir / name
        if not args.synthetic_only and copy_stock_wav(project_root, output_path, name):
            continue
        write_wav(output_path, builder())
        print(f"wrote synthetic Assets/sounds/{name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
