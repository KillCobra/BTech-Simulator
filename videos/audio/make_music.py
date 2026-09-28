"""Bunk Master trailer score: an original 30 s chip-pop cue, synthesized from scratch.

128 BPM, 4/4, 16 bars = exactly 30.0 s. Bar numbers here are the same bars the film's
cues use (src/film/cues.ts), so every hit lands on the frame it was written for.

Run from videos/:  uv run --with numpy --with scipy python audio/make_music.py
Writes public/audio/trailer.wav (48 kHz stereo) and public/audio/hits.json.
"""
import json
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
BPM = 128.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 16
LENGTH = BARS * BAR  # 30.0 s
N = int(round(LENGTH * SR))
rng = np.random.default_rng(7)
OUT = Path(__file__).resolve().parent.parent / "public" / "audio"


def at(bar, beat=1, frac=0.0):
    """Seconds at a 1-based bar and beat; frac is a share of one beat."""
    return ((bar - 1) * 4 + (beat - 1) + frac) * BEAT


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


class Bus:
    def __init__(self):
        self.l = np.zeros(N + SR * 4)
        self.r = np.zeros(N + SR * 4)

    def add(self, t, sig, gain=1.0, pan=0.0):
        i = int(round(t * SR))
        if i < 0:
            sig = sig[-i:]
            i = 0
        end = min(i + len(sig), len(self.l))
        sig = sig[: end - i]
        lg = gain * np.cos((pan + 1) * np.pi / 4) * np.sqrt(2)
        rg = gain * np.sin((pan + 1) * np.pi / 4) * np.sqrt(2)
        self.l[i:end] += sig * lg
        self.r[i:end] += sig * rg

    def stereo(self):
        return np.stack([self.l, self.r])


def env(n, a=0.002, d=0.1, s=0.0, r=0.05, hold=None):
    """ADSR over n samples; hold = seconds before release (default: whole note minus release)."""
    t = np.arange(n) / SR
    hold = (n / SR - r) if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip(1 - (t - hold) / max(r, 1e-6), 0, 1)
    return e * np.where(t > hold, rel, 1)


def polyblep(p, dt):
    out = np.zeros_like(p)
    m = p < dt
    x = p[m] / dt[m] if np.ndim(dt) else p[m] / dt
    out[m] = x + x - x * x - 1
    m2 = p > 1 - dt
    x = (p[m2] - 1) / (dt[m2] if np.ndim(dt) else dt)
    out[m2] = x * x + x + x + 1
    return out


def phase(freq, n, start=None):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    p = np.cumsum(f / SR) + (rng.random() if start is None else start)
    return p % 1.0, f / SR


def saw(freq, n, start=None):
    p, dt = phase(freq, n, start)
    return 2 * p - 1 - polyblep(p, dt)


def pulse(freq, n, width=0.5):
    p, dt = phase(freq, n, 0.0)
    a = 2 * p - 1 - polyblep(p, dt)
    p2 = (p + (1 - width)) % 1.0
    b = 2 * p2 - 1 - polyblep(p2, dt)
    return (a - b) * 0.5


def tri(freq, n):
    p, _ = phase(freq, n, 0.0)
    return 2 * np.abs(2 * p - 1) - 1


def lp(sig, cutoff, order=2):
    sos = butter(order, min(cutoff, SR * 0.45), "low", fs=SR, output="sos")
    return sosfilt(sos, sig)


def hp(sig, cutoff, order=2):
    sos = butter(order, cutoff, "high", fs=SR, output="sos")
    return sosfilt(sos, sig)


def bp(sig, lo, hi, order=2):
    sos = butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return sosfilt(sos, sig)


def sweep_lp(sig, c0, c1, block=256, curve=2.0):
    """Low-pass whose cutoff glides from c0 to c1 (exponential), block-wise."""
    out = np.zeros_like(sig)
    nb = (len(sig) + block - 1) // block
    zi = np.zeros((1, 2))
    for k in range(nb):
        u = (k / max(nb - 1, 1)) ** curve
        c = c0 * (c1 / c0) ** u
        sos = butter(2, min(c, SR * 0.45), "low", fs=SR, output="sos")
        seg = sig[k * block:(k + 1) * block]
        y, zi = sosfilt(sos, seg, zi=zi)
        out[k * block:k * block + len(seg)] = y
    return out


def noise(n):
    return rng.standard_normal(n)


# ----------------------------------------------------------------------------- instruments

def kick(big=False):
    n = int(SR * (0.9 if big else 0.42))
    t = np.arange(n) / SR
    f = 46 + 130 * np.exp(-t / 0.045) + (80 * np.exp(-t / 0.006))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (0.32 if big else 0.16))
    click = hp(noise(n), 2500) * np.exp(-t / 0.004) * 0.35
    return np.tanh((body + click) * 1.6) * 0.9


def clap():
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    e = np.zeros(n)
    for off in (0.0, 0.011, 0.022):
        e += np.where(t >= off, np.exp(-(t - off) / (0.012 if off < 0.02 else 0.13)), 0)
    body = bp(noise(n), 900, 5200) * e
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05) * 0.5
    return (body * 0.7 + tone) * 0.8


def snare(level=1.0):
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    body = bp(noise(n), 1200, 9000) * np.exp(-t / 0.07)
    tone = np.sin(2 * np.pi * 210 * t) * np.exp(-t / 0.04)
    return (body * 0.6 + tone * 0.5) * level


def hat(open_=False):
    n = int(SR * (0.3 if open_ else 0.06))
    t = np.arange(n) / SR
    return hp(noise(n), 7500, 4) * np.exp(-t / (0.09 if open_ else 0.014)) * 0.5


def crash(length=2.2):
    n = int(SR * length)
    t = np.arange(n) / SR
    return lp(hp(noise(n), 4200, 2), 11000) * np.exp(-t / 0.6) * 0.3


def pizz(midi, dur):
    n = int(SR * dur)
    s = saw(hz(midi), n) * 0.5 + tri(hz(midi), n) * 0.5
    s = lp(s, 1800)
    return s * env(n, 0.002, 0.09, 0.0, 0.03)


def bass(midi, dur):
    n = int(SR * dur)
    s = saw(hz(midi), n, 0.0) * 0.6 + saw(hz(midi) * 1.005, n) * 0.4
    t = np.arange(n) / SR
    s = lp(s, 900)
    sub = np.sin(2 * np.pi * hz(midi - 12 if midi > 40 else midi) * t) * 0.7
    return np.tanh((s + sub) * 1.4) * env(n, 0.003, 0.2, 0.7, 0.03) * 0.8


def supersaw(midis, dur, cutoff=5000, voices=6, spread=0.18):
    n = int(SR * dur)
    left = np.zeros(n)
    right = np.zeros(n)
    for m in midis:
        for v in range(voices):
            det = (v / (voices - 1) - 0.5) * spread
            f = hz(m) * 2 ** (det / 12)
            s = saw(f, n)
            if v % 2:
                left += s
            else:
                right += s
    k = 1.0 / (len(midis) * voices * 0.5)
    return lp(left * k, cutoff), lp(right * k, cutoff)


def chip_lead(midi, dur, vib=True):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = hz(midi) * (1 + (0.006 * np.sin(2 * np.pi * 6 * t) * np.clip((t - 0.12) / 0.1, 0, 1) if vib else 0))
    s = pulse(f, n, 0.25) * 0.7 + pulse(f * 2, n, 0.5) * 0.12
    s = lp(s, 7000)
    return s * env(n, 0.004, 0.25, 0.6, 0.04)


def blip(midi, dur=0.09, width=0.5):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = hz(midi) * (1 + 0.5 * np.exp(-t / 0.01))
    return pulse(f, n, width) * np.exp(-t / (dur * 0.35)) * 0.5


def bell_ring(length=1.6):
    """An old electric school bell: a struck metal gong hammered ~22 times a second."""
    n = int(SR * length)
    t = np.arange(n) / SR
    partials = [(1.0, 1.0), (2.76, 0.6), (5.40, 0.35), (8.93, 0.2), (1.5, 0.3)]
    base = 1180.0
    s = sum(a * np.sin(2 * np.pi * base * r * t + rng.random() * 6) for r, a in partials)
    hammer = 0.55 + 0.45 * np.abs(np.sin(np.pi * 22 * t))
    shape = np.clip(t / 0.01, 0, 1) * np.where(t < length - 0.5, 1.0, np.exp(-(t - (length - 0.5)) / 0.18))
    return s * hammer * shape * 0.22


def tick(high=True):
    n = int(SR * 0.05)
    t = np.arange(n) / SR
    s = bp(noise(n), 2500 if high else 1600, 9000) * np.exp(-t / 0.006)
    s += np.sin(2 * np.pi * (2400 if high else 1700) * t) * np.exp(-t / 0.01) * 0.5
    return s * 0.6


def riser(length):
    n = int(SR * length)
    t = np.arange(n) / SR
    u = t / length
    nz = noise(n)
    s = sweep_lp(nz, 300, 12000, curve=1.6) * (u ** 1.5)
    tone = saw(hz(50) * 2 ** (u * 3), n) * (u ** 2) * 0.25
    return (s * 0.35 + lp(tone, 4000)) * 0.9


def whoosh(length=0.5):
    """Swells to a peak at `length * 0.7`, then tails off."""
    n = int(SR * length)
    t = np.arange(n) / SR
    pk = length * 0.7
    e = np.where(t < pk, (t / pk) ** 2.2, np.exp(-(t - pk) / 0.07))
    s = hp(sweep_lp(noise(n), 350, 7000, curve=1.0), 250)
    return s * e * 0.6, pk


def impact():
    n = int(SR * 2.5)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * (38 + 60 * np.exp(-t / 0.08)) * t) * np.exp(-t / 0.7)
    grit = lp(noise(n), 1800) * np.exp(-t / 0.25) * 0.5
    return np.tanh((boom + grit) * 1.5) * 0.8


def ching():
    """Cash register style sparkle for money and items."""
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / d) for f, d in ((2637, 0.25), (3520, 0.2), (5274, 0.12)))
    return s * 0.18


# ----------------------------------------------------------------------------- arrangement

drums, bassb, chords, lead, fx, pads = Bus(), Bus(), Bus(), Bus(), Bus(), Bus()
kicks = []
hits = []  # (time, label) for the film to verify against


def K(t, big=False, g=1.0):
    drums.add(t, kick(big), g)
    kicks.append(t)


# Chords (D minor): i  VI  III  VII
DM, BB, F, C = [62, 65, 69], [58, 62, 65], [57, 60, 65], [55, 60, 64]
PROG = [DM, BB, F, C]
ROOTS = [38, 34, 41, 36]

# Hook: (16th step, length in 16ths, midi) per bar of the progression.
HOOK = [
    [(0, 2, 74), (3, 1, 77), (4, 2, 81), (6, 2, 79), (8, 2, 77), (10, 1, 76), (11, 1, 77), (12, 4, 74)],
    [(0, 2, 70), (2, 2, 74), (4, 2, 77), (7, 1, 74), (8, 3, 77), (11, 1, 79), (12, 4, 81)],
    [(0, 2, 81), (3, 1, 84), (4, 2, 81), (6, 2, 79), (8, 2, 77), (10, 2, 79), (12, 4, 81)],
    [(0, 2, 79), (2, 2, 76), (4, 2, 72), (6, 2, 76), (8, 2, 79), (10, 2, 84), (12, 2, 81), (14, 2, 79)],
]
S16 = BEAT / 4

# --- Bars 1-2: the bell, the clock, a sneaky bass --------------------------------------
fx.add(at(1), bell_ring(1.7), 0.9)
hits.append((at(1), "bell"))
for b in range(8):  # clock ticking through the intro
    fx.add(at(1 + b // 4, b % 4 + 1), tick(b % 2 == 0), 0.55, pan=0.3 if b % 2 else -0.3)
SNEAK = [[38, None, 41, None, 43, None, 44, 45], [None, 45, None, 44, 43, None, 41, None]]
for bar in range(1, 5):
    for k, m in enumerate(SNEAK[(bar - 1) % 2]):
        if m is not None:
            bassb.add(at(bar, 1 + k // 2, 0.5 * (k % 2)), pizz(m + 12, BEAT * 0.45), 0.55)
# soft Dm pad under it, filter opening across bars 1-4
pl, pr = supersaw([50, 57, 62, 65], BAR * 4, cutoff=900, voices=4, spread=0.12)
fade = np.clip(np.arange(len(pl)) / (SR * 1.5), 0, 1)
pads.add(at(1), sweep_lp(pl, 500, 3500, curve=2.5) * fade, 0.16, pan=-0.6)
pads.add(at(1), sweep_lp(pr, 500, 3500, curve=2.5) * fade, 0.16, pan=0.6)
# the teaser: four chip notes answering the bell
for k, m in enumerate([74, 77, 81, 79]):
    lead.add(at(2, 1 + k), chip_lead(m, BEAT * 0.4, vib=False), 0.18, pan=0.2)

# --- Bars 3-4: drums in, build, riser, gap ---------------------------------------------
for beat in (1, 3):
    K(at(3, beat))
for beat in (1, 2, 3, 4):
    K(at(4, beat), g=0.9)
for bar in (3, 4):
    for k in range(8):
        drums.add(at(bar, 1 + k // 2, 0.5 * (k % 2)), hat(), 0.5 if k % 2 else 0.25, pan=0.25)
    drums.add(at(bar, 2), clap(), 0.55)
    drums.add(at(bar, 4), clap(), 0.55)
# snare roll across bar 4: 8ths, then 16ths, then 32nds, crescendo
roll = [(at(4, 1, 0.5 * k), 0.25 + 0.05 * k) for k in range(4)]
roll += [(at(4, 3, 0.25 * k), 0.45 + 0.05 * k) for k in range(4)]
roll += [(at(4, 4, 0.125 * k), 0.65 + 0.04 * k) for k in range(6)]
for t, g in roll:
    drums.add(t, snare(), g)
fx.add(at(3, 1), riser(BAR * 2 - BEAT * 0.25), 0.55)
# suspicion alarm blips climbing on each beat of bar 4
for k in range(4):
    fx.add(at(4, 1 + k), blip(79 + k * 3, 0.12, 0.25), 0.22)
hits.append((at(4, 4), "run"))


def groove(bar, full=True, arp=False, lead_on=True, open_hats=False):
    ci = (bar - 1) % 4
    for beat in range(1, 5):
        K(at(bar, beat))
    for beat in (2, 4):
        drums.add(at(bar, beat), clap(), 0.62)
    for k in range(8):
        drums.add(at(bar, 1 + k // 2, 0.5 * (k % 2)), hat(open_hats and k % 2 == 1), 0.42 if k % 2 else 0.18, pan=0.25)
    if full:
        for k in range(16):
            if k % 4 == 2:
                continue
            drums.add(at(bar, 1 + k // 4, 0.25 * (k % 4)), hat(), 0.12, pan=-0.35)
    # bass: root / octave eighths
    r = ROOTS[ci]
    for k in range(8):
        m = r + (12 if k % 2 else 0)
        bassb.add(at(bar, 1 + k // 2, 0.5 * (k % 2)), bass(m, BEAT * 0.48), 0.55)
    # offbeat supersaw stabs
    for beat in range(1, 5):
        l, rr = supersaw([n + 12 for n in PROG[ci]] + [PROG[ci][0]], BEAT * 0.42, cutoff=5500)
        e = env(len(l), 0.003, 0.12, 0.35, 0.05)
        chords.add(at(bar, beat, 0.5), l * e, 0.30, pan=-0.7)
        chords.add(at(bar, beat, 0.5), rr * e, 0.30, pan=0.7)
    if lead_on:
        for step, ln, m in HOOK[ci]:
            lead.add(at(bar, 1 + step // 4, 0.25 * (step % 4)), chip_lead(m, S16 * ln * 0.92), 0.26, pan=-0.1)
            lead.add(at(bar, 1 + step // 4, 0.25 * (step % 4) + 0.75), chip_lead(m, S16 * ln * 0.8), 0.07, pan=0.5)  # echo
    if arp:
        notes = [n + 12 for n in PROG[ci]]
        for k in range(16):
            lead.add(at(bar, 1 + k // 4, 0.25 * (k % 4)), blip(notes[k % 3] + (12 if k % 6 > 2 else 0), S16 * 0.9, 0.125), 0.10, pan=0.45 * (1 if k % 2 else -1))


# --- Bars 5-8: DROP 1 ------------------------------------------------------------------
drums.add(at(5), impact(), 0.8)
drums.add(at(5), crash(), 0.8)
hits.append((at(5), "drop"))
for bar in range(5, 9):
    groove(bar)
# style pops (bar 7): ascending coin chimes on each beat, then the x5 on 7.4.5
for k, m in enumerate([84, 88, 91, 96]):
    fx.add(at(7, 1 + k), blip(m, 0.16, 0.5), 0.22, pan=0.3)
fx.add(at(7, 4, 0.5), ching(), 0.8)
# phone tiles (bar 8): seven pops on 16ths from 8.1.25
for k in range(7):
    fx.add(at(8, 1, 0.25 + 0.5 * k), blip(86 + [0, 3, 5, 7, 10, 12, 15][k], 0.07, 0.25), 0.18, pan=-0.4 + 0.13 * k)
w, pk = whoosh(0.55)
fx.add(at(9) - pk, w, 0.9)

# --- Bars 9-12: DROP 2, one map per bar --------------------------------------------------
for bar in range(9, 13):
    groove(bar, arp=True, open_hats=True)
    drums.add(at(bar), crash(1.4), 0.28)
    if bar > 9:
        w, pk = whoosh(0.45)
        fx.add(at(bar) - pk, w, 0.8)
    hits.append((at(bar), f"map{bar - 8}"))
# exit markers popping on beats 2-4 of each map bar
for bar in range(9, 12):
    for beat in (2, 3, 4):
        fx.add(at(bar, beat, 0.0), blip(91 + beat, 0.06, 0.5), 0.12, pan=0.2)
# friends joining (bar 12, beats 3-4): eight quick pops
for k in range(8):
    fx.add(at(12, 3, 0.25 * k), blip(79 + [0, 2, 4, 7, 9, 12, 14, 16][k], 0.06, 0.5), 0.14, pan=-0.5 + k / 7)

# --- Bars 13-14: half-time lift, items, ranks, the big riser ----------------------------
for bar in (13, 14):
    ci = 1 + (bar - 13)  # Bb then C
    K(at(bar, 1))
    K(at(bar, 3), g=0.8)
    drums.add(at(bar, 3), clap(), 0.6)
    for k in range(8):
        drums.add(at(bar, 1 + k // 2, 0.5 * (k % 2)), hat(), 0.3 if k % 2 else 0.12, pan=0.25)
    l, rr = supersaw([n + 12 for n in PROG[ci]] + [PROG[ci][0] - 12], BAR, cutoff=6000)
    e = env(len(l), 0.01, 0.6, 0.6, 0.1)
    chords.add(at(bar), l * e, 0.34, pan=-0.7)
    chords.add(at(bar), rr * e, 0.34, pan=0.7)
    r = ROOTS[ci]
    for k in range(4):
        bassb.add(at(bar, 1 + k), bass(r + (12 if k % 2 else 0), BEAT * 0.9), 0.55)
    notes = [n + 12 for n in PROG[ci]]
    for k in range(16):
        lead.add(at(bar, 1 + k // 4, 0.25 * (k % 4)), blip(notes[k % 3] + (12 if k >= 8 else 0), S16 * 0.9, 0.125), 0.12 + 0.004 * k, pan=0.45 * (1 if k % 2 else -1))
# items on each beat of bar 13
for beat in range(1, 5):
    fx.add(at(13, beat), ching(), 0.55)
    hits.append((at(13, beat), f"item{beat}"))
# ranks on 14.1, 14.2, 14.3, 14.3.5, 14.4: rising chip steps
for k, (beat, frac) in enumerate([(1, 0), (2, 0), (3, 0), (3, 0.5), (4, 0)]):
    fx.add(at(14, beat, frac), chip_lead(79 + [0, 3, 7, 10, 15][k], BEAT * 0.4, vib=False), 0.2)
fx.add(at(13, 1), riser(BAR * 2 - BEAT * 0.2), 0.5)
roll = [(at(14, 3, 0.25 * k), 0.35 + 0.05 * k) for k in range(4)] + [(at(14, 4, 0.125 * k), 0.55 + 0.05 * k) for k in range(7)]
for t, g in roll:
    drums.add(t, snare(), g)
w, pk = whoosh(0.7)
fx.add(at(15) - pk, w, 1.0)

# --- Bars 15-16: the logo, the final chord, the bell ------------------------------------
drums.add(at(15), impact(), 1.0)
drums.add(at(15), crash(2.6), 0.9)
hits.append((at(15), "logo"))
groove(15, lead_on=True)
# 16.1: the last chord hit, long ring-out, and the bell again
K(at(16), big=True)
drums.add(at(16), crash(3.0), 0.8)
l, rr = supersaw([50, 57, 62, 65, 69, 74], BAR * 1.2, cutoff=4500, voices=7)
e = env(len(l), 0.004, 0.7, 0.35, 0.8)
chords.add(at(16), l * e, 0.42, pan=-0.7)
chords.add(at(16), rr * e, 0.42, pan=0.7)
bassb.add(at(16), bass(38, BAR * 1.1) * env(int(SR * BAR * 1.1), 0.003, 0.8, 0.3, 0.6), 0.6)
lead.add(at(16), chip_lead(86, BEAT * 1.5), 0.24)
fx.add(at(16, 2), bell_ring(1.4), 0.45)
hits.append((at(16), "final"))

# ----------------------------------------------------------------------------- mix

def sidechain(n, depth=0.65, release=0.13):
    g = np.ones(n)
    t = np.arange(n) / SR
    for tk in kicks:
        i = int(tk * SR)
        j = min(n, i + int(SR * 0.4))
        g[i:j] = np.minimum(g[i:j], 1 - depth * np.exp(-(t[i:j] - tk) / release))
    return g


def reverb(st, seconds=1.8, mix=0.18):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    out = []
    for ch in range(2):
        ir = noise(n) * np.exp(-t / (seconds / 5))
        ir = lp(ir, 6000)
        ir /= np.sqrt(np.sum(ir ** 2))
        out.append(fftconvolve(st[ch], ir)[: st.shape[1]])
    return np.stack(out) * mix


M = len(drums.l)
sc = sidechain(M)
dr = drums.stereo()
bs = bassb.stereo() * sc
ch = chords.stereo() * sc
pd = pads.stereo()
ld = lead.stereo()
fxx = fx.stereo()
wet = reverb(ch * 0.8 + ld * 0.9 + pd + fxx * 0.3, 2.2, 0.26)
wet = np.stack([lp(wet[0], 5000), lp(wet[1], 5000)])
mix = dr * 0.95 + bs * 0.9 + ch + pd + ld + fxx + wet
mix = np.stack([hp(mix[0], 28), hp(mix[1], 28)])
mix = mix[:, :N]
# fade the tail into the last frames
tail = np.ones(N)
f0 = int((LENGTH - 0.6) * SR)
tail[f0:] = np.linspace(1, 0, N - f0) ** 2
mix *= tail
# gentle glue + ceiling
peak = np.max(np.abs(mix))
mix = np.tanh(mix / peak * 1.35) / np.tanh(1.35)
mix *= 10 ** (-1.0 / 20)

OUT.mkdir(parents=True, exist_ok=True)
pcm = (np.clip(mix.T, -1, 1) * 32767).astype("<i2")
with wave.open(str(OUT / "trailer.wav"), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
json.dump({"bpm": BPM, "bars": BARS, "length": LENGTH, "hits": [{"t": round(t, 4), "label": l} for t, l in hits]},
          open(OUT / "hits.json", "w"), indent=1)
rms = np.sqrt(np.mean(mix ** 2))
print(f"wrote {OUT / 'trailer.wav'}  {LENGTH:.2f}s  rms {20 * np.log10(rms):.1f} dBFS")
