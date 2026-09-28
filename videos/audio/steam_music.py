"""Bunk Master Steam store trailer: original 45 s score + SFX, synthesized from scratch (no samples).

128 BPM, 24 bars, A minor. The game's chase progression (Am-F-G-E, autoload/sfx.gd `_make_chase`), its square
arps and bouncing octave bass, its SFX recipes (bell, siren, pickup, spotted alarm, click, paper, win arpeggio)
ported from autoload/sfx.gd. The section map is src/steam/timeline.json, the same grid the visuals read.

Hook (the thing to remember): a tresillo cell, dotted-8th, dotted-8th, 8th, on the same three notes per chord:
E E A | C C F | D D G | G# B E. Heard on a music box in the hush (bar 1), compressed two chords per bar in both
drops, as sneaky plucks in groove A, as the full lead in groove B, on bells in the lift, and in C major at the end.

Map (bar.beat):
  0.0  school bell RING + low boom, clock ticks; the bell stops dead -> hush (drone, ticks, music box hook)
  2-3  tense classroom: heartbeat, low 8th pulse, filtered arps, riser -> 3.3 "RUN!" stab, snare pickup
  4    DROP 1: compressed hook, 808s on the hook rhythm, 16th arps     5  full groove, down-sweep out
  6-9  groove A, sneaky: muted plucks play the hook low, walking sub, snaps; 8.0 stop-time hit, silent to 8.2
  10-13 groove B: kick on every beat, 16th hats, lead hook with dotted-8th echo, octave layer in 12-13
  14-15 lift: F G | C, gang claps, tambourine, bells play the hook in major
  16-17 build: F G | E7, quarter kicks -> 8ths, snare roll in 17, noise + pitch riser; silence 17.3.5 -> 18.0
  18-19 DROP 2 (biggest): wide supersaws, distorted 808, hook doubled at the octave, crash every bar
  20-21 triumph: C G | F E, the game's win arpeggio as the arp, major hook on top
  22.0 logo slam: impact + A major stab + bell; 22-23 ring-out, clock ticks bookend; fade over the last 1.2 s

SFX: every src/steam/sfx/*.json is a list of [name, bar, beat, gain]. Each sound is placed so its transient
lands on the beat (whoosh: its peak; paper: the hit after the throw; riser: its END lands on the cue, it starts a
bar earlier). Unknown names and unreadable files warn and are skipped, so this is safe to re-run at any time.
The score already plays the bell on 0.0 and 22.0, the impact on 22.0 and the clock ticks; act cues that
duplicate those (within 40 ms) are skipped in the mix so nothing doubles. However dense the cue lists get, the
SFX stay under the music: a music-keyed gain holds small sounds 7 dB under the music's short-term loudness and the
big ones (impact, crash, stamp, slap, bell) within +1 dB of it, with floors so they still read in the quiet parts.
Sounds cued inside the two written silences play; tails that run into them from earlier are cut.

Run from videos/:  uv run --with numpy --with scipy python audio/steam_music.py
  --demo        use a built-in cue list with every SFX (writes to out/steam/audio-demo/ instead)
Writes public/audio/steam/{music,sfx,mix}.wav: 44.1 kHz stereo 16-bit, exactly 45.00 s.
music.wav and mix.wav are mastered to -14 LUFS integrated, true peak -1.5 dBTP (4x oversampled limiter);
sfx.wav is the SFX stem at the level it sits in the mix.
"""
import json
import sys
import wave
import zlib
from pathlib import Path

import numpy as np
from scipy.ndimage import minimum_filter1d, uniform_filter1d
from scipy.signal import butter, fftconvolve, lfilter, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parent.parent
TL = json.loads((ROOT / "src/steam/timeline.json").read_text())
SR = 44100
BPM = TL["bpm"]
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = TL["bars"]
DUR = BARS * BAR
END = int(round(DUR * SR))  # exactly 45.00 s
N = END + SR * 3  # tail room while building, trimmed at the end
DEMO = "--demo" in sys.argv
TARGET_LUFS = -14.0
CEILING_DBTP = -1.5

R = np.random.default_rng(128)  # music randomness; each SFX cue gets its own seeded generator


def T(bar, beat=0.0):
    return (bar * 4 + beat) * BEAT


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def noise(n):
    return R.standard_normal(n)


# ================================================================ DSP primitives
def _blep(x, dt):
    y = np.zeros_like(x)
    m = x < dt
    u = x[m] / dt[m]
    y[m] = 2 * u - u * u - 1
    m = x > 1 - dt
    u = (x[m] - 1) / dt[m]
    y[m] = u * u + 2 * u + 1
    return y


def osc(kind, f, n, phase0=None, duty=0.5, aa=True):
    """Oscillator with PolyBLEP anti-aliasing on saw and square (clean high leads)."""
    f = np.broadcast_to(np.asarray(f, float), (n,))
    p0 = R.random() if phase0 is None else phase0
    ph = p0 + np.cumsum(f) / SR
    x = ph % 1.0
    dt = np.clip(f / SR, 1e-6, 0.5)
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    if kind == "tri":
        return 4 * np.abs(x - 0.5) - 1
    if kind == "saw":
        y = 2 * x - 1
        return y - _blep(x, dt) if aa else y
    if kind == "square":
        y = np.where(x < duty, 1.0, -1.0)
        if aa:
            y = y + _blep(x, dt) - _blep((x - duty) % 1.0, dt)
        return y
    raise ValueError(kind)


def _sos(kind, fc, order):
    if kind == "band":
        lo, hi = fc
        return butter(order, [max(lo, 10), min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return butter(order, min(max(fc, 10), SR * 0.45), kind, fs=SR, output="sos")


def lp(x, fc, order=2):
    return sosfilt(_sos("low", fc, order), x, axis=0)


def hp(x, fc, order=2):
    return sosfilt(_sos("high", fc, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("band", (lo, hi), order), x, axis=0)


def sweep(x, fcs, kind="low", q=1.0, chunk=256):
    """Time-varying filter: cutoff follows fcs (one value per sample), filter state carried across chunks."""
    n = len(x)
    out = np.zeros_like(x)
    zi = None
    for a in range(0, n, chunk):
        b_ = min(n, a + chunk)
        fc = float(np.mean(fcs[a:b_]))
        if kind == "band":
            sos = _sos("band", (fc / (1 + 0.5 / q), fc * (1 + 0.5 / q)), 1)
        else:
            sos = _sos(kind, fc, 2)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2) + x.shape[1:])
        out[a:b_], zi = sosfilt(sos, x[a:b_], axis=0, zi=zi)
    return out


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.05, hold=None):
    t = np.arange(n) / SR
    hold = n / SR - r if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    return e * np.clip(1 - (t - hold) / max(r, 1e-6), 0, 1)


def fade_edges(x, a=0.002, r=0.01):
    n = len(x)
    t = np.arange(n) / SR
    e = np.clip(t / a, 0, 1) * np.clip((n / SR - t) / r, 0, 1)
    return x * (e if x.ndim == 1 else e[:, None])


def stereo(x, pan=0.0):
    if x.ndim == 2:
        return x
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    return np.stack([x * l, x * r], 1) * np.sqrt(2)


def place(dst, t, x, gain=1.0):
    i = int(round(t * SR))
    if x.ndim == 1:
        x = stereo(x)
    if i < 0:
        x = x[-i:]
        i = 0
    j = min(len(dst), i + len(x))
    if j > i:
        dst[i:j] += x[: j - i] * gain


# ================================================================ buses
BUSES = ["kick", "drums", "bass", "keys", "lead", "fx"]
BUS = {k: np.zeros((N, 2)) for k in BUSES}
REV = np.zeros((N, 2))  # plate send
DLY = np.zeros((N, 2))  # dotted-8th ping-pong send
KICKS = []  # (time, strength) for the sidechain
OWNED = {"bell": [], "impact": [], "tick": []}  # music-owned hits; duplicate act cues are skipped


def add(bus, t, x, gain=1.0, pan=0.0, rev=0.0, dly=0.0):
    x = stereo(x, pan)
    place(BUS[bus], t, x, gain)
    if rev:
        place(REV, t, x, gain * rev)
    if dly:
        place(DLY, t, x, gain * dly)


# ================================================================ drums
def kick(kind="main"):
    dur, base, sweep_, dec = {"soft": (0.3, 50, 70, 11), "main": (0.42, 47, 150, 7.5), "big": (0.8, 43, 170, 3.8)}[kind]
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = base + sweep_ * np.exp(-t * 30) + 45 * np.exp(-t * 7)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * dec)
    x = np.tanh(body * (1.6 if kind != "big" else 2.1))
    if kind != "soft":
        x += 0.28 * hp(noise(n), 1800) * np.exp(-t * 320)  # beater click
        x += 0.25 * np.sin(2 * np.pi * np.cumsum(f * 2) / SR) * np.exp(-t * 30)  # knock
    return fade_edges(x * 0.9, 0.0005, 0.03)


def snare(tight=False):
    n = int(SR * (0.18 if tight else 0.3))
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(215 - 40 * t / t[-1]) / SR) * np.exp(-t * 28)
    body += 0.5 * np.sin(2 * np.pi * 330 * t) * np.exp(-t * 40)
    wires = bp(noise(n), 1800, 10000) * np.exp(-t * (30 if tight else 17))
    return fade_edges((0.55 * body + 0.8 * wires) * 0.75)


def clap(spread=0.0):
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    e = np.zeros(n)
    for k, off in enumerate([0, 0.009, 0.019, 0.027]):
        i = int(off * SR)
        e[i:] += np.exp(-t[: n - i] * (180 if k < 3 else 19)) * (0.8 if k < 3 else 1.0)
    x = bp(noise(n), 1000, 6000) * e
    return fade_edges(x * 0.7)


def gang_clap():
    """Four people clapping: small timing offsets, spread in stereo (the friends)."""
    out = np.zeros((int(SR * 0.35), 2))
    for off, pan, g in [(0.0, -0.6, 1.0), (0.007, 0.5, 0.9), (0.013, -0.2, 0.8), (0.018, 0.75, 0.7)]:
        c = stereo(clap() * g, pan)
        i = int(off * SR)
        out[i:i + len(c)] += c[: len(out) - i]
    return out * 0.6


HATF = np.array([205.3, 304.4, 369.6, 522.7, 540.0, 800.0])


def hat(open_=False):
    n = int(SR * (0.35 if open_ else 0.06))
    t = np.arange(n) / SR
    metal = sum(osc("square", f * 1.47, n, aa=False) for f in HATF) / 6
    x = hp(bp(metal, 6000, 14000) * 0.8 + hp(noise(n), 8000) * 0.35, 5000)
    return fade_edges(x * np.exp(-t * (9 if open_ else 75)) * 0.6, 0.0005, 0.01)


def shaker():
    n = int(SR * 0.07)
    t = np.arange(n) / SR
    return hp(noise(n), 6000) * np.sin(np.pi * t / t[-1]) ** 2 * 0.35


def tamb():
    n = int(SR * 0.16)
    t = np.arange(n) / SR
    jingles = sum(np.sin(2 * np.pi * f * t + R.random() * 6) for f in [5400, 6800, 7900, 9100, 10400]) / 5
    x = (0.6 * jingles + 0.5 * hp(noise(n), 7000)) * np.exp(-t * 26) * (0.8 + 0.2 * np.sin(2 * np.pi * 60 * t))
    return fade_edges(x * 0.45)


def snap():
    n = int(SR * 0.09)
    t = np.arange(n) / SR
    x = bp(noise(n), 1600, 4200) * np.exp(-t * 90) + np.sin(2 * np.pi * 2300 * t) * np.exp(-t * 140) * 0.3
    return fade_edges(x * 0.9)


def crash(length=2.4, bright=1.0):
    n = int(SR * length)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for ch in range(2):
        metal = sum(osc("square", f * (2.3 + 0.07 * ch), n, aa=False) for f in HATF) / 6
        x = hp(noise(n), 3500) * 0.8 + bp(metal, 3000, 12000) * 0.6
        out[:, ch] = x * (np.exp(-t * 2.0 / bright) * 0.85 + 0.15 * np.exp(-t * 12))
    return fade_edges(out * 0.35, 0.0005, 0.1)


def reverse_cymbal(dur):
    return crash(dur * 1.6)[: int(dur * SR)][::-1] * np.linspace(0, 1, int(dur * SR))[:, None] ** 2


def tom(f):
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.6 * np.exp(-t * 25))) / SR) * np.exp(-t * 9)
    x += 0.2 * bp(noise(n), 400, 3000) * np.exp(-t * 40)
    return fade_edges(np.tanh(x * 1.5) * 0.7)


def tick(tock=False):
    """Classroom clock: a woody click (tick, tock)."""
    n = int(SR * 0.09)
    t = np.arange(n) / SR
    f = 1450 if tock else 1900
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * 70) + 0.5 * np.sin(2 * np.pi * f * 2.7 * t) * np.exp(-t * 120)
    x += 0.4 * hp(noise(n), 3000) * np.exp(-t * 400)
    return fade_edges(x * 0.55, 0.0003)


def boom(length=2.5, f0=38, drop=90):
    n = int(SR * length)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * np.cumsum(f0 + drop * np.exp(-t * 10)) / SR) * np.exp(-t * 1.9)
    body = lp(noise(n), 1500) * np.exp(-t * 8)
    return fade_edges(np.tanh(sub * 2.0 + body * 0.7) * 0.9, 0.0005, 0.2)


def K(bar, beat, kind="main", g=0.9):
    add("kick", T(bar, beat), kick(kind), g)
    KICKS.append((T(bar, beat), {"soft": 0.35, "main": 1.0, "big": 1.0}[kind]))


def D(bar, beat, x, g, pan=0.0, rev=0.05):
    add("drums", T(bar, beat), x, g, pan=pan, rev=rev)


# ================================================================ synth voices
def pluck(kind, f, dur, cutoff=4000, duty=0.5, decay=6.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    x = osc(kind, f, n, duty=duty) * np.exp(-t * decay)
    return fade_edges(lp(x, cutoff), 0.002, min(0.012, dur * 0.3))


def muted(f, dur):
    """Palm-muted pluck: bright tick that closes fast, then a round tail."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    raw = 0.6 * osc("square", f, n, duty=0.3) + 0.5 * osc("tri", f, n)
    bright, dark = lp(raw, 3500), lp(raw, 700)
    e = np.exp(-t * 45)
    x = (bright * e + dark * (1 - e)) * np.exp(-t * 9)
    return fade_edges(x, 0.001, min(0.02, dur * 0.3))


def fm_bell(f, dur=1.6, index=2.5, decay=3.0):
    """Glockenspiel / music box: FM with an inharmonic modulator."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    idx = index * np.exp(-t * 7)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.5 * t)) * np.exp(-t * decay)
    x += 0.25 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * decay * 1.8)
    return fade_edges(x * 0.6, 0.001, 0.05)


def supersaw(freqs, dur, cutoff=2200, voices=7, spread=0.2, width=0.8, env=None):
    n = int(SR * dur)
    out = np.zeros((n, 2))
    dets = np.linspace(-1, 1, voices)
    for f in freqs:
        for k, d in enumerate(dets):
            x = osc("saw", f * 2 ** (d * spread / 12), n)
            pan = d * width
            out += stereo(x, pan) / np.sqrt(2)
    out = lp(out, cutoff) / (len(freqs) * np.sqrt(voices) * 1.6)
    e = adsr(n, a=0.03, d=0.4, s=0.85, r=0.25) if env is None else env
    return out * e[:, None]


def stab(freqs, dur=0.35, bright=7000, dark=900):
    """Brass-ish chord stab: saws through a snapping filter envelope, plus a square sub-octave."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for i, f in enumerate(freqs):
        for d, pan in [(-0.1, -0.5), (0.1, 0.5), (0.0, 0.0)]:
            out += stereo(osc("saw", f * 2 ** (d / 12), n), pan) / np.sqrt(2)
    sub = osc("square", freqs[0] / 2, n, duty=0.5)
    out += stereo(lp(sub, 1200)) * 0.4
    e = np.exp(-t * 22)
    out = lp(out, bright) * e[:, None] + lp(out, dark) * (1 - e)[:, None]
    return fade_edges(out * adsr(n, a=0.003, d=0.15, s=0.5, r=0.08)[:, None] / (len(freqs) * 2), 0.001, 0.05)


def bass808(f, dur, glide_from=None, drive=2.5, decay=0.9, rel=0.03):
    n = int(SR * dur)
    t = np.arange(n) / SR
    ff = np.full(n, f)
    if glide_from:
        ff = f * (glide_from / f) ** np.exp(-t * 16)
    x = np.sin(2 * np.pi * np.cumsum(ff) / SR)
    x = np.tanh(x * drive * np.exp(-t * decay * 0.5)) / np.tanh(drive) * np.exp(-t * decay)
    return fade_edges(x * 0.75, 0.003, rel)


def sub(f, dur):
    n = int(SR * dur)
    x = np.sin(2 * np.pi * f * np.arange(n) / SR)
    return fade_edges(x, 0.004, min(0.03, dur * 0.3))


def lead_voice(f, dur, cutoff=4200, glide_from=None, vib=0.0045, fat=1.0):
    n = int(SR * (dur + 0.04))
    t = np.arange(n) / SR
    ff = np.full(n, float(f))
    if glide_from:
        ff = f * (glide_from / f) ** np.exp(-t * 45)
    ff = ff * (1 + vib * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.15) / 0.12, 0, 1))
    x = 0.55 * osc("square", ff, n) + 0.4 * osc("saw", ff * 1.004, n) + 0.3 * fat * osc("saw", ff * 0.9965, n)
    x = x * adsr(n, a=0.004, d=0.14, s=0.72, r=0.04, hold=dur)
    return fade_edges(lp(x, cutoff), 0.001, 0.02)


# ================================================================ harmony
CH = {  # (bass root, pad voicing)
    "Am": (45, [57, 60, 64]), "F": (41, [57, 60, 65]), "G": (43, [55, 59, 62]), "E": (40, [56, 59, 64]),
    "E7": (40, [56, 62, 64]), "C": (48, [55, 60, 64]), "A": (45, [57, 61, 64]),
}
HARM = [
    (0, 0, "Am"), (3, 0, "F"), (3, 2, "E"),
    (4, 0, "Am"), (4, 2, "F"), (5, 0, "G"), (5, 2, "E"),
    (6, 0, "Am"), (7, 0, "F"), (8, 0, "G"), (9, 0, "E"),
    (10, 0, "Am"), (11, 0, "F"), (12, 0, "G"), (13, 0, "E"),
    (14, 0, "F"), (14, 2, "G"), (15, 0, "C"),
    (16, 0, "F"), (16, 2, "G"), (17, 0, "E"), (17, 2, "E7"),
    (18, 0, "Am"), (18, 2, "F"), (19, 0, "G"), (19, 2, "E"),
    (20, 0, "C"), (20, 2, "G"), (21, 0, "F"), (21, 2, "E"),
    (22, 0, "A"),
]


def chord_at(bar, beat=0.0):
    tb = bar * 4 + beat + 1e-9
    name = HARM[0][2]
    for b_, bt, nm in HARM:
        if b_ * 4 + bt <= tb:
            name = nm
    return name


def chord_spans(bar0, bar1):
    """(start_time, dur, name) for each chord change between two bars."""
    pts = [(b_ * 4 + bt, nm) for b_, bt, nm in HARM if bar0 * 4 <= b_ * 4 + bt < bar1 * 4]
    if not pts or pts[0][0] > bar0 * 4:
        pts.insert(0, (bar0 * 4, chord_at(bar0)))
    out = []
    for i, (bt, nm) in enumerate(pts):
        nxt = pts[i + 1][0] if i + 1 < len(pts) else bar1 * 4
        out.append((bt * BEAT, (nxt - bt) * BEAT, nm))
    return out


# The hook. One bar per chord (beat, midi, beats).
HOOK = {
    "Am": [(0, 76, 0.7), (0.75, 76, 0.7), (1.5, 81, 0.95), (2.5, 79, 0.45), (3, 76, 0.45), (3.5, 74, 0.45)],
    "F": [(0, 72, 0.7), (0.75, 72, 0.7), (1.5, 77, 0.95), (2.5, 76, 0.45), (3, 72, 0.45), (3.5, 69, 0.45)],
    "G": [(0, 74, 0.7), (0.75, 74, 0.7), (1.5, 79, 0.95), (2.5, 83, 0.45), (3, 81, 0.45), (3.5, 79, 0.45)],
    "E": [(0, 80, 0.7), (0.75, 83, 0.7), (1.5, 88, 1.4), (3, 86, 0.2), (3.25, 83, 0.2), (3.5, 80, 0.45)],
}
CELL = {k: v[:3] for k, v in HOOK.items()}  # the tresillo cell, fits in half a bar


def third_below(m, name):
    """Nearest chord tone at least a minor third under m (a consonant harmony line)."""
    pcs = {x % 12 for x in CH[name][1]}
    h = m - 3
    while h % 12 not in pcs:
        h -= 1
    return h


def cell(name, half_len=True):
    c = CELL[name]
    return [(b_, m, 0.7 if i < 2 else 0.45) for i, (b_, m, _) in enumerate(c)]


# ================================================================ arrangement
def arp_16ths(bar, beats, gain, cutoff, octave=12, kind="square", duty=0.25, pan=0.5, rev=0.08, pattern=None):
    for beat in beats:
        for s in range(4):
            bt = beat + s / 4
            nm = chord_at(bar, bt)
            root, tones = CH[nm]
            seq = tones + [tones[0] + 12]
            step = int(bt * 4)
            if pattern is not None:
                m = pattern(nm, step)
            else:
                idx = step % 4 if (bar + int(bt // 2)) % 2 == 0 else 3 - step % 4  # up, then down (sfx.gd)
                m = seq[idx] + octave
            c = cutoff(bar, bt) if callable(cutoff) else cutoff
            add("keys", T(bar, bt), pluck(kind, midi(m), BEAT / 4 * 0.9, cutoff=c, duty=duty, decay=9),
                gain, pan=pan if s % 2 else -pan, rev=rev)


def pad_bars(bar0, bar1, gain, cutoff, voices=5, width=0.95, spread=0.15, rev=0.3, octave=0):
    for t0, dur, nm in chord_spans(bar0, bar1):
        fr = [midi(m + octave) for m in CH[nm][1]]
        x = supersaw(fr, dur + 0.2, cutoff=cutoff, voices=voices, width=width, spread=spread)
        add("keys", t0, hp(x, 180), gain, rev=rev)


def lead_line(bar, notes, gain, cutoff=4200, octave=0, pan=0.08, rev=0.12, dly=0.28, fat=1.0, beat_off=0.0):
    for bb, m, ln in notes:
        x = lead_voice(midi(m + octave), BEAT * ln, cutoff=cutoff, fat=fat)
        add("lead", T(bar, bb + beat_off), hp(x, 200), gain, pan=pan, rev=rev, dly=dly)


def compressed_hook(bar, gain, octave=0, **kw):
    """Two chords per bar: each half plays the tresillo cell of its chord."""
    for half in range(2):
        nm = chord_at(bar, half * 2)
        nm = "E" if nm == "E7" else nm
        lead_line(bar, cell(nm), gain, octave=octave, beat_off=half * 2, **kw)


def bass_on_cell(bar, gain, drive=2.5, sub_oct=-12):
    """808s locked to the hook rhythm, two chords per bar."""
    for half in range(2):
        nm = chord_at(bar, half * 2)
        root = CH[nm][0]
        for i, (bb, ln) in enumerate([(0, 0.7), (0.75, 0.7), (1.5, 0.5)]):
            f = midi(root + sub_oct)
            gl = midi(root + sub_oct + 12) if (i == 0 and half == 0) else None
            add("bass", T(bar, half * 2 + bb), bass808(f, BEAT * ln, glide_from=gl, drive=drive), gain)


def octave_bass(bar, gain, beats=range(4), cutoff=900, with_sub=True):
    """The game's chase bass: bouncing octave 8ths, square, plus a sine sub under the root."""
    for beat in beats:
        for e in range(2):
            bt = beat + e * 0.5
            root = CH[chord_at(bar, bt)][0]
            m = root + (12 if e else 0)
            x = pluck("square", midi(m), BEAT * 0.45, cutoff=cutoff, duty=0.125, decay=3)
            add("bass", T(bar, bt), hp(x, 90), gain)
            if with_sub and not e:
                add("bass", T(bar, bt), sub(midi(root - 12), BEAT * 0.45) * 0.9, gain * 1.6)


def build_music():
    # ------------------------------------------------ 0-1 cold open: bell RING, it stops dead, hush
    add("fx", 0.0, music_bell(1.3), 1.25, rev=0.35)
    OWNED["bell"].append(0.0)
    add("fx", 0.0, boom(3.0, 41, 70), 0.55, rev=0.1)
    drone_n = int(T(4) * SR)
    t = np.arange(drone_n) / SR
    drone = 0.6 * np.sin(2 * np.pi * midi(33) * t) + 0.3 * np.sin(2 * np.pi * midi(40) * t + 1)
    swell = np.clip(t / 1.2, 0, 1) * (0.55 + 0.45 * np.clip((t - T(2)) / (T(3, 3) - T(2)), 0, 1))
    add("bass", 0.0, fade_edges(drone * swell, 0.3, 0.05), 0.2)
    tt = np.arange(int(T(3) * SR)) / SR
    dark = supersaw([midi(m) for m in [45, 52, 57, 60]], T(3), voices=5, spread=0.12, width=0.6,
                    env=np.clip(tt / 1.5, 0, 1) * (0.2 + 0.8 * np.clip((tt - T(1, 2)) / (T(3) - T(1, 2)), 0, 1)))
    dark = fade_edges(sweep(dark, np.linspace(350, 1300, len(dark))), 0.01, 0.35)
    add("keys", 0.0, dark, 0.4, rev=0.35)
    pad_bars(3, 4, 0.3, 1500, voices=5, rev=0.3)
    for s in range(15):  # tick-tock every beat through the RUN! (3.3); 8ths join in bar 3
        add("drums", T(0, s), tick(s % 2 == 1), 0.42 if s >= 8 else 0.34, pan=0.25 if s % 2 else -0.25, rev=0.25)
        OWNED["tick"].append(T(0, s))
    for s in range(3):
        add("drums", T(3, s + 0.5), tick(True), 0.2, pan=0.4, rev=0.2)
    # music box: the hook, alone in the dark
    for bb, m, ln in HOOK["Am"]:
        add("keys", T(1, bb), fm_bell(midi(m + 12), 1.4, index=1.6, decay=2.6), 0.08, pan=0.2, rev=0.7)

    # ------------------------------------------------ 2-3 tense classroom
    for bar, beats in [(2, (0, 2)), (3, (0, 1, 2))]:
        for bb in beats:  # heartbeat, lub-dub
            K(bar, bb, "soft", 0.75)
            K(bar, bb + 0.25, "soft", 0.45)
    for bar in (2, 3):
        for e in range(8):
            bt = e * 0.5
            if bar == 3 and bt >= 3:
                break
            root = CH[chord_at(bar, bt)][0]
            x = pluck("square", midi(root), BEAT * 0.4, cutoff=400 + 500 * (bar - 2) + 60 * e, duty=0.2, decay=5)
            add("bass", T(bar, bt), x + sub(midi(root - 12), BEAT * 0.4) * 0.8, 0.2 + 0.06 * (bar - 2))
    arp_16ths(2, range(4), 0.07, lambda b_, bt: 700 + 180 * ((b_ - 2) * 4 + bt), octave=12)
    arp_16ths(3, range(3), 0.08, lambda b_, bt: 700 + 180 * ((b_ - 2) * 4 + bt), octave=12)
    add("fx", T(2), riser(T(3, 3) - T(2), 250, 7000), 0.3, rev=0.15)
    # 3.3 RUN!
    add("keys", T(3, 3), stab([midi(m) for m in [64, 68, 71, 76]], 0.5), 0.9, rev=0.3)
    K(3, 3, "big", 0.85)
    D(3, 3, snare(), 0.6, rev=0.15)
    D(3, 3, crash(1.0), 0.35)
    for i, bb in enumerate([3.5, 3.625, 3.75, 3.875]):
        D(3, bb, snare(tight=True), 0.25 + 0.1 * i, rev=0.1)
    add("fx", T(3, 3.25), reverse_cymbal(BEAT * 0.75), 0.5)

    # ------------------------------------------------ 4-5 DROP 1
    K(4, 0, "big", 1.0)
    D(4, 0, crash(2.4), 0.6)
    add("fx", T(4), boom(2.0, 40, 80), 0.45)
    for bar in (4, 5):
        for bb in (0, 1, 2, 3):
            if not (bar == 4 and bb == 0):
                K(bar, bb, "main", 0.8)
        K(bar, 2.75, "main", 0.5)
        for bb in (1, 3):
            D(bar, bb, snare(), 0.55, rev=0.12)
            D(bar, bb, clap(), 0.4, pan=0.1, rev=0.12)
        for h in range(16):
            D(bar, h / 4, hat(), 0.36 if h % 2 else 0.24, pan=0.35)
        for ob in (0.5, 1.5, 2.5, 3.5):
            D(bar, ob, hat(True), 0.14, pan=-0.3)
        bass_on_cell(bar, 0.55)
        compressed_hook(bar, 0.2)
        compressed_hook(bar, 0.07, octave=-12, pan=-0.2, dly=0.0)
        for half in range(2):
            nm = chord_at(bar, half * 2)
            for bb, m, ln in cell(nm):
                add("keys", T(bar, half * 2 + bb), stab([midi(x) for x in CH[nm][1]], BEAT * ln), 0.2, rev=0.15)
    arp_16ths(4, range(4), 0.1, 5000)
    arp_16ths(5, range(4), 0.1, 5000)
    pad_bars(4, 6, 0.35, 2600)
    # down-sweep out of the drop (tape-stop feel) into the sneaky groove
    n = int(BEAT * 0.5 * SR)
    tt = np.arange(n) / SR
    dn = osc("saw", midi(76) * 2 ** (-2 * tt / tt[-1]), n) * np.linspace(1, 0, n)
    add("fx", T(5, 3.5), hp(lp(dn, 2500), 200) * 0.3, 1.0, rev=0.3)

    # ------------------------------------------------ 6-9 groove A: sneaky
    walk = {"Am": [0, 0, 7, 12, 0, 3], "F": [0, 0, 7, 12, 0, 4], "G": [0, 0, 7, 12, 0, 4], "E": [0, 0, 7, 12, 0, 3]}
    for bar in range(6, 10):
        nm = chord_at(bar)
        root = CH[nm][0]
        nxt = CH[chord_at(bar + 1)][0] if bar < 9 else 45
        steps = list(zip([0, 1, 1.5, 2, 3], walk[nm][:5])) + [(3.5, None)]
        for bb, off in steps:
            if bar == 8 and 0.0 < bb < 2:
                continue  # stop-time
            m = (nxt - 1 if nxt - 1 >= root - 5 else nxt + 1) if off is None else root + off
            add("bass", T(bar, bb), sub(midi(m - 12), BEAT * 0.38) * 0.9 + muted(midi(m), BEAT * 0.38) * 0.5, 0.42)
        for bb in (0, 2.5):
            if not (bar == 8 and bb == 0):
                K(bar, bb, "main", 0.6)
        for bb in (1, 3):
            if not (bar == 8 and bb == 1):
                D(bar, bb, snap(), 0.42, pan=0.15, rev=0.2)
        for h in range(8):
            if bar == 8 and h < 4:
                continue
            D(bar, h / 2, hat(), 0.14 if h % 2 else 0.09, pan=-0.4)
        for h in range(16):
            if bar == 8 and h < 8:
                continue
            if bar >= 7:
                D(bar, h / 4, shaker(), 0.2 if h % 4 == 2 else 0.1, pan=0.45, rev=0.0)
        D(bar, 3.75, tick(True), 0.2, pan=-0.2, rev=0.2)
        for bb, m, ln in HOOK[nm]:  # the hook, low and muted
            if bar == 8 and 0 < bb < 2:
                continue
            add("keys", T(bar, bb), muted(midi(m - 12), BEAT * ln * 0.6), 0.3, pan=0.15, rev=0.12, dly=0.25)
            add("keys", T(bar, bb), muted(midi(m), BEAT * ln * 0.45), 0.1, pan=-0.2, rev=0.1)
        if bar != 8:
            pad_bars(bar, bar + 1, 0.16, 900, voices=3, rev=0.25)
    # 8.0 stop-time: everyone hits the downbeat, then silence until 8.2
    K(8, 0, "big", 0.85)
    add("keys", T(8), stab([midi(m) for m in [55, 59, 62, 67]], 0.3), 0.8, rev=0.1)
    D(8, 0, snare(), 0.45, rev=0.1)
    D(8, 0, crash(0.35), 0.3)
    K(8, 2, "main", 0.7)
    D(8, 2, snare(tight=True), 0.35)
    pad_bars(8, 9, 0.16, 900, voices=3, rev=0.25)
    # bar 9: tension up into groove B
    for i, bb in enumerate(np.arange(3, 4, 0.125)):
        D(9, bb, snare(tight=True), 0.15 + 0.05 * i, rev=0.08)
    add("fx", T(9, 1), riser(T(10) - T(9, 1), 500, 9000), 0.22)

    # ------------------------------------------------ 10-13 groove B: busy, the full hook
    for bar in range(10, 14):
        for bb in range(4):
            K(bar, bb, "main", 0.9 if bb in (0, 2) else 0.8)
        for bb in (1, 3):
            D(bar, bb, snare(), 0.5, rev=0.12)
            D(bar, bb, clap(), 0.45, pan=-0.1, rev=0.15)
        for h in range(16):
            D(bar, h / 4, hat(), [0.26, 0.16, 0.38, 0.16][h % 4], pan=0.35)
        for ob in (0.5, 1.5, 2.5, 3.5):
            D(bar, ob, hat(True), 0.15, pan=-0.3)
        nm = chord_at(bar)
        root = CH[nm][0]
        for bb, ln in [(0, 0.7), (0.75, 0.7), (1.5, 0.9), (2.5, 0.45), (3, 0.45), (3.5, 0.45)]:
            add("bass", T(bar, bb), bass808(midi(root - 12), BEAT * ln, drive=2.2,
                                             glide_from=midi(root + 12) if bb == 0 and bar == 10 else None), 0.5)
        octave_bass(bar, 0.14, cutoff=1400, with_sub=False)
        lead_line(bar, HOOK[nm], 0.2)
        if bar >= 12:
            lead_line(bar, HOOK[nm], 0.06, octave=12, pan=-0.3, dly=0.1)
            lead_line(bar, [(b_, third_below(m, nm), ln) for b_, m, ln in HOOK[nm]], 0.05, pan=0.4, dly=0)
    for bar in (10, 12):
        D(bar, 0, crash(2.2), 0.45)
    for bar in range(10, 14):
        arp_16ths(bar, range(4), 0.09, 4200 if bar < 12 else 5600)
    pad_bars(10, 14, 0.3, 2400)
    for i, (bb, f) in enumerate([(3, 220), (3.25, 180), (3.5, 150), (3.75, 120)]):
        D(13, bb, tom(f), 0.5, rev=0.12)

    # ------------------------------------------------ 14-15 lift: brighter, major, friends clapping
    D(14, 0, crash(2.5), 0.4)
    for bar in (14, 15):
        for bb in range(4):
            K(bar, bb, "main", 0.72)
        for bb in (1, 3):
            D(bar, bb, gang_clap(), 0.8, rev=0.2)
        if bar == 15:
            for bb in (2.5, 3.5):
                D(bar, bb, gang_clap(), 0.55, rev=0.2)
        for h in range(8):
            D(bar, h / 2, tamb(), 0.38 if h % 2 else 0.24, pan=0.45, rev=0.1)
        for h in range(16):
            D(bar, h / 4, shaker(), 0.12, pan=-0.45, rev=0.0)
        octave_bass(bar, 0.34, cutoff=1500)
    lift = [(0, 81, 0.7), (0.75, 81, 0.7), (1.5, 84, 0.5), (2, 83, 0.7), (2.75, 83, 0.7), (3.5, 86, 0.5)]
    lift2 = [(0, 84, 0.7), (0.75, 84, 0.7), (1.5, 88, 1.0), (2.5, 86, 0.45), (3, 84, 0.45), (3.5, 83, 0.45)]
    for bar, line in [(14, lift), (15, lift2)]:
        for bb, m, ln in line:
            add("keys", T(bar, bb), fm_bell(midi(m), 1.2, index=2.2, decay=3.5), 0.26, pan=0.15, rev=0.3, dly=0.3)
            add("keys", T(bar, bb), fm_bell(midi(m + 12), 0.8, index=1.0, decay=5), 0.06, pan=-0.3, rev=0.3)
        lead_line(bar, line, 0.085, cutoff=3000, dly=0.15)
    for bar in (14, 15):
        arp_16ths(bar, range(4), 0.08, 6000, octave=24, kind="tri", duty=0.5, pan=0.4)
    pad_bars(14, 16, 0.3, 3600, voices=7, width=0.9)
    add("fx", T(15, 2), reverse_cymbal(BEAT * 2), 0.35)

    # ------------------------------------------------ 16-17 build, half a beat of silence before 18
    for bb in range(4):
        K(16, bb, "main", 0.75)
        D(16, bb, snare(tight=True), 0.3, rev=0.1)
    for bb in np.arange(0, 3.5, 0.5):
        K(17, bb, "main", 0.7 + 0.03 * bb)
    roll = [(b_, 0.5) for b_ in (0, 0.5, 1, 1.5)] + [(2 + i * 0.25, 0.25) for i in range(4)] + \
           [(3 + i * 0.125, 0.125) for i in range(4)]
    for i, (bb, _) in enumerate(roll):
        D(17, bb, snare(tight=True), 0.25 + 0.025 * i, rev=0.1)
    for bar in (16, 17):
        for e in range(8):
            bt = e * 0.5
            if bar == 17 and bt >= 3.5:
                break
            root = CH[chord_at(bar, bt)][0]
            g = 0.25 + 0.03 * ((bar - 16) * 8 + e)
            add("bass", T(bar, bt), pluck("square", midi(root), BEAT * 0.42, cutoff=900, duty=0.125, decay=3)
                + sub(midi(root - 12), BEAT * 0.42) * 0.7, g)
    arp_16ths(16, range(4), 0.09, lambda b_, bt: 1500 + 800 * ((b_ - 16) * 4 + bt), octave=12)
    arp_16ths(17, range(4), 0.1, lambda b_, bt: 1500 + 800 * ((b_ - 16) * 4 + bt), octave=24)
    pad_bars(16, 18, 0.3, 3000, voices=7)
    add("fx", T(16), riser(T(17, 3.5) - T(16), 300, 11000), 0.4, rev=0.1)
    n = int((T(17, 3.5) - T(17)) * SR)
    tt = np.arange(n) / SR
    pr = osc("saw", midi(52) * 2 ** (2 * (tt / tt[-1]) ** 1.5), n) + osc("saw", midi(52.1) * 2 ** (2 * (tt / tt[-1]) ** 1.5), n)
    add("fx", T(17), hp(lp(pr, 5000), 250) * (tt / tt[-1]) ** 1.5 * 0.2, 1.0, rev=0.2)
    lead_line(16, [(0, 81, 1.9), (2, 83, 1.9)], 0.08, cutoff=3000)
    lead_line(17, [(0, 80, 1.9), (2, 83, 1.4)], 0.1, cutoff=3500)

    # ------------------------------------------------ 18-19 DROP 2: biggest
    K(18, 0, "big", 1.0)
    add("fx", T(18), boom(2.6, 34, 110), 0.6)
    for bar in (18, 19):
        D(bar, 0, crash(2.6, 1.2), 0.65)
        for bb in range(4):
            if not (bar == 18 and bb == 0):
                K(bar, bb, "big" if bb == 0 else "main", 0.95)
        K(bar, 1.75, "main", 0.45)
        K(bar, 3.75, "main", 0.45)
        for bb in (1, 3):
            D(bar, bb, snare(), 0.6, rev=0.15)
            D(bar, bb, clap(), 0.5, pan=0.1, rev=0.2)
            D(bar, bb, gang_clap(), 0.35, rev=0.2)
        for h in range(16):
            D(bar, h / 4, hat(), [0.28, 0.17, 0.4, 0.17][h % 4], pan=0.35)
        for ob in (0.5, 1.5, 2.5, 3.5):
            D(bar, ob, hat(True), 0.17, pan=-0.3)
        bass_on_cell(bar, 0.68, drive=4.0)
        compressed_hook(bar, 0.21)
        compressed_hook(bar, 0.1, octave=12, pan=-0.25, dly=0.12)
        compressed_hook(bar, 0.07, octave=-12, pan=0.25, dly=0.0)
        for half in range(2):
            nm = chord_at(bar, half * 2)
            for bb, m, ln in cell(nm):
                add("keys", T(bar, half * 2 + bb), stab([midi(x) for x in CH[nm][1] + [CH[nm][1][0] + 12]], BEAT * ln), 0.34, rev=0.2)
        arp_16ths(bar, range(4), 0.09, 6500, octave=12)
        arp_16ths(bar, range(4), 0.05, 7000, octave=24, pan=0.7)
    pad_bars(18, 20, 0.42, 4200, voices=9, width=1.0, spread=0.25)
    for i, bb in enumerate(np.arange(3, 4, 0.25)):
        D(19, bb, tom(200 - 25 * i), 0.4, rev=0.1)

    # ------------------------------------------------ 20-21 triumph: the win arpeggio
    D(20, 0, crash(2.4), 0.55)
    for bar in (20, 21):
        for bb in range(4):
            K(bar, bb, "main", 0.88)
        for bb in (1, 3):
            D(bar, bb, snare(), 0.45, rev=0.15)
            D(bar, bb, gang_clap(), 0.6, rev=0.2)
        for h in range(16):
            D(bar, h / 4, hat(), [0.26, 0.16, 0.36, 0.16][h % 4], pan=0.35)
        for h in range(8):
            D(bar, h / 2, tamb(), 0.3 if h % 2 else 0.18, pan=-0.45)
        octave_bass(bar, 0.4, cutoff=1300)
    # sfx.gd win arpeggio 72 76 79 84 79 84 (+ a turn back down), moved through C G F E
    tops = {"C": 72, "G": 71, "F": 72, "E": 71}
    shapes = {"C": [0, 4, 7, 12, 7, 12, 7, 4], "G": [0, 3, 8, 12, 8, 12, 8, 3], "F": [0, 5, 9, 12, 9, 12, 9, 5],
              "E": [0, 5, 9, 12, 9, 12, 9, 5]}
    for bar in (20, 21):
        for half in range(2):
            nm = chord_at(bar, half * 2)
            for s, iv in enumerate(shapes[nm]):
                m = tops[nm] + iv
                add("keys", T(bar, half * 2 + s / 4),
                    pluck("square", midi(m), BEAT / 4 * 0.95, cutoff=6000, duty=0.3, decay=6), 0.13,
                    pan=0.3 if s % 2 else -0.3, rev=0.12)
    tri1 = [(0, 79, 0.7), (0.75, 79, 0.7), (1.5, 84, 0.45), (2, 83, 0.7), (2.75, 83, 0.7), (3.5, 86, 0.45)]
    tri2 = [(0, 84, 0.7), (0.75, 84, 0.7), (1.5, 89, 0.45), (2, 88, 0.7), (2.75, 86, 0.7), (3.5, 83, 0.45)]
    lead_line(20, tri1, 0.19)
    lead_line(21, tri2, 0.19)
    lead_line(20, tri1, 0.07, octave=12, pan=-0.3, dly=0.1)
    lead_line(21, tri2, 0.07, octave=12, pan=-0.3, dly=0.1)
    pad_bars(20, 22, 0.38, 4200, voices=9, width=1.0, spread=0.22)
    add("fx", T(21, 2), reverse_cymbal(BEAT * 2), 0.5)
    for i, bb in enumerate([3, 3.25, 3.5, 3.75]):
        D(21, bb, tom(210 - 30 * i), 0.45, rev=0.1)

    # ------------------------------------------------ 22.0 logo slam, ring-out
    K(22, 0, "big", 1.0)
    add("fx", T(22), boom(3.5, 36, 100), 0.75, rev=0.15)
    OWNED["impact"].append(T(22))
    D(22, 0, crash(4.0, 1.5), 0.7)
    D(22, 0, snare(), 0.55, rev=0.4)
    D(22, 0, gang_clap(), 0.5, rev=0.4)
    add("keys", T(22), stab([midi(m) for m in [57, 61, 64, 69, 73]], 1.2), 1.0, rev=0.5)
    add("bass", T(22), bass808(midi(33), DUR - T(22), glide_from=midi(45), drive=3.0, decay=1.1, rel=1.0), 0.7)
    add("fx", T(22), music_bell(2.9, midi(85)), 0.8, rev=0.4)  # tuned to the C# of A major
    OWNED["bell"].append(T(22))
    ring = supersaw([midi(m) for m in [57, 61, 64, 69, 76]], BAR * 2, voices=9, width=1.0, spread=0.18,
                    env=adsr(int(BAR * 2 * SR), a=0.02, d=1.0, s=0.6, r=1.5))
    ring = sweep(ring, np.geomspace(5000, 900, len(ring)))
    add("keys", T(22), hp(ring, 150), 0.55, rev=0.5)
    for bb, m, ln in CELL["Am"]:  # hook bookend: E E A sits in A major too
        add("keys", T(22, 2 + bb), fm_bell(midi(m + 12), 1.6, index=1.8, decay=2.4), 0.16, rev=0.6, dly=0.3)
    for bb in (0, 1, 2, 3):  # the classroom clock again
        add("drums", T(23, bb), tick(bb % 2 == 1), 0.28, pan=0.25 if bb % 2 else -0.25, rev=0.3)
        OWNED["tick"].append(T(23, bb))
    add("keys", T(23), fm_bell(midi(81), 2.0, index=1.2, decay=1.8), 0.1, rev=0.6)


def riser(dur, f0=300, f1=8000):
    n = int(dur * SR)
    u = np.arange(n) / n
    fc = f0 * (f1 / f0) ** u
    x = sweep(noise(n), fc, kind="band", q=1.5)
    x = x / (np.abs(x).max() + 1e-9)
    tone_ = osc("saw", 110 * 2 ** (3 * u), n) * 0.15
    return fade_edges((x * 0.8 + lp(tone_, 3000)) * u ** 2, 0.01, 0.004)


# ================================================================ SFX (recipes from autoload/sfx.gd, RATE 22050)
GD_RATE = 22050


def gd_tone(b, start, dur, f0, f1, amp, wave_="sine", decay=0.0, lpc=1.0, vib_hz=0.0, vib=0.0):
    """Port of sfx.gd `_tone`: linear glide, one-pole low-pass, exp decay, vibrato, 4 ms / 20 ms ramps."""
    i0 = int(start * SR)
    n = min(int(dur * SR), len(b) - i0)
    if n <= 0:
        return
    i = np.arange(n)
    f = f0 + (f1 - f0) * i / n
    if vib > 0:
        f = f * (1 + vib * np.sin(2 * np.pi * vib_hz * i / SR))
    ph = (np.cumsum(f) / SR) % 1.0
    x = {"sine": np.sin(2 * np.pi * ph), "square": np.where(ph < 0.5, 1.0, -1.0),
         "tri": 4 * np.abs(ph - 0.5) - 1, "saw": 2 * ph - 1}[wave_]
    if wave_ in ("square", "saw"):
        x = lp(x, 10000)  # the game runs at 22050 Hz
    if lpc < 1.0:
        a = 1 - np.sqrt(1 - lpc)  # same cutoff at twice the rate
        x = lfilter([a], [1, -(1 - a)], x)
    env = np.minimum(i / (0.004 * SR), 1) * np.minimum((n - i) / (min(0.02, dur * 0.3) * SR), 1)
    if decay > 0:
        env = env * np.exp(-decay * i / SR)
    b[i0:i0 + n] += x * env * amp


def gd_noise(b, start, dur, amp, lpc, decay):
    i0 = int(start * SR)
    n = min(int(dur * SR), len(b) - i0)
    if n <= 0:
        return
    i = np.arange(n)
    x = lp(R.uniform(-1, 1, n), 10000)
    a = 1 - np.sqrt(1 - lpc)
    x = lfilter([a], [1, -(1 - a)], x)
    env = np.minimum(i / 40.0, 1) * np.minimum((n - i) / (min(0.01, dur * 0.3) * SR), 1) * np.exp(-decay * i / SR)
    b[i0:i0 + n] += x * env * amp


def buf(sec):
    return np.zeros(int(sec * SR))


def music_bell(length, f0=1100.0):
    """sfx.gd `_make_bell` (clapper hammering at 22 Hz), trailer size: stereo, an octave body, hard stop."""
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for ch, det in enumerate([1.0, 1.003]):
        k = f0 / 1100.0
        s = sum(np.sin(2 * np.pi * f * k * det * t) * a for f, a in [(1100, 0.5), (2200, 0.18), (3036, 0.12), (4410, 0.05)])
        s += 0.22 * np.sin(2 * np.pi * 550 * k * det * t)
        strike = (t * 22.0 + 0.3 * ch) % 1.0
        trem = 0.35 + 0.65 * np.exp(-strike * 5.0)
        out[:, ch] = s * trem
    fade = np.clip((length - t) / 0.06, 0, 1) * np.minimum(t / 0.002, 1)
    return out * fade[:, None] * 0.55


def s_bell():
    b = buf(2.5)
    t = np.arange(len(b)) / SR
    for f, a in [(1100, 0.5), (2200, 0.18), (3036, 0.12), (4410, 0.05)]:
        b += np.sin(2 * np.pi * f * t) * a
    strike = (t * 22.0) % 1.0
    b *= (0.35 + 0.65 * np.exp(-strike * 5.0)) * np.clip((2.5 - t) / 0.4, 0, 1) * np.minimum(t / 0.01, 1) * 0.55
    return b


def s_blip():
    b = buf(0.08)
    gd_tone(b, 0, 0.055, 440, 400, 0.4, "square", 35.0, 0.35)
    gd_tone(b, 0, 0.06, 880, 800, 0.15, "square", 40.0, 0.35)
    return b


def s_pop():
    n = int(SR * 0.12)
    t = np.arange(n) / SR
    f = 380 + 1100 * (1 - np.exp(-t * 40))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 32)
    x += 0.3 * hp(R.standard_normal(n), 2000) * np.exp(-t * 500)
    return fade_edges(x * 0.6, 0.0005)


def s_ping():  # sfx.gd "pickup"
    b = buf(0.35)
    gd_tone(b, 0.0, 0.12, 1318.5, 1318.5, 0.3, "tri", 12.0)
    gd_tone(b, 0.08, 0.27, 1975.5, 1975.5, 0.3, "tri", 9.0)
    gd_tone(b, 0.08, 0.27, 3951.0, 3951.0, 0.05, "sine", 14.0)
    return b


def s_star():  # pickup, one step higher, with a sparkle
    b = buf(0.6)
    gd_tone(b, 0.0, 0.08, 1318.5, 1318.5, 0.3, "tri", 12.0)
    gd_tone(b, 0.06, 0.08, 1568.0, 1568.0, 0.3, "tri", 12.0)
    gd_tone(b, 0.12, 0.45, 2637.0, 2637.0, 0.3, "tri", 7.0, 1.0, 9.0, 0.006)
    gd_tone(b, 0.12, 0.45, 5274.0, 5274.0, 0.05, "sine", 9.0)
    return b


def s_whoosh(dur=0.5):
    n = int(SR * dur)
    u = np.arange(n) / n
    x = sweep(R.standard_normal(n), 500 * 12 ** u, kind="band", q=0.8)
    return x / (np.abs(x).max() + 1e-9) * np.sin(np.pi * u) ** 3 * 0.7


def s_stamp():
    n = int(SR * 0.4)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(55 + 130 * np.exp(-t * 40)) / SR) * np.exp(-t * 9)
    slap = bp(R.standard_normal(n), 300, 5000) * np.exp(-t * 50)
    return fade_edges(np.tanh((thump * 1.3 + slap * 0.9) * 1.6) * 0.8, 0.0005)


def s_shuffle():
    out = np.zeros(int(SR * 0.5))
    for k in range(7):
        m = int(SR * 0.04)
        c = bp(R.standard_normal(m), 1500, 6000) * np.exp(-np.arange(m) / SR * 90)
        i = int(k * 0.058 * SR)
        out[i:i + m] += c * (0.5 + 0.1 * k)
    return out * 0.6


def s_psst():
    n = int(SR * 0.45)
    t = np.arange(n) / SR
    ps = bp(R.standard_normal(n), 3500, 9000) * np.clip(t / 0.03, 0, 1) * np.exp(-t * 5)
    ps[: int(0.05 * SR)] *= 0.4  # the "p"
    return fade_edges(ps * 0.7)


def s_spotted():  # sfx.gd alarm_spotted
    b = buf(0.4)
    gd_tone(b, 0.0, 0.14, 520, 1300, 0.28, "square", 0.0, 0.3)
    gd_tone(b, 0.13, 0.22, 1568, 1568, 0.25, "tri", 10.0)
    gd_tone(b, 0.13, 0.22, 3136, 3136, 0.06, "sine", 14.0)
    return b


def s_whir():
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    x = lp(osc("saw", 90 + 30 * np.sin(2 * np.pi * 3 * t), n), 1400) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * t))
    x += 0.2 * bp(R.standard_normal(n), 2000, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 30 * t))
    return x * np.sin(np.pi * t / 0.6) * 0.5


def s_siren():  # sfx.gd _make_siren, two sweeps
    dur = 2.4
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 600 + 500 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 1.2))
    x = np.tanh(2.5 * np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.3
    return fade_edges(lp(x, 9000), 0.01, 0.4)


def s_click():  # sfx.gd click
    b = buf(0.06)
    gd_tone(b, 0.0, 0.04, 1800, 1200, 0.25, "tri", 90.0)
    gd_noise(b, 0.0, 0.01, 0.15, 0.7, 200.0)
    return b * 1.6


def s_crash():  # trolley into staff: thump + metal clang + rattle
    n = int(SR * 1.2)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(50 + 90 * np.exp(-t * 30)) / SR) * np.exp(-t * 8)
    clang = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in [(523, 6), (1187, 7), (1790, 9), (2710, 12)]) * 0.25
    rattle = bp(R.standard_normal(n), 2000, 9000) * np.exp(-t * 7) * (0.5 + 0.5 * (np.sin(2 * np.pi * 26 * t) > 0))
    return fade_edges(np.tanh(thump * 1.4 + clang + rattle * 0.5) * 0.8, 0.0005, 0.1)


PAPER_THROW = 0.28


def s_paper():  # a throw, then sfx.gd paper (crackled noise) on the hit
    b = buf(0.3)
    gd_noise(b, 0.0, 0.3, 0.5, 0.35, 6.0)
    g = np.repeat(R.uniform(0.2, 1.4, len(b) // int(0.08 * SR / 10) + 1), int(0.08 * SR / 10))[: len(b)]
    hit = b * g * 1.4
    throw = s_whoosh(PAPER_THROW) * 0.35
    return np.concatenate([throw, hit])


def s_spray():
    n = int(SR * 0.9)
    t = np.arange(n) / SR
    return fade_edges(hp(R.standard_normal(n), 2500) * np.clip(t / 0.02, 0, 1) * np.exp(-t * 2.5) * 0.5)


def s_slap():
    n = int(SR * 0.2)
    t = np.arange(n) / SR
    x = lp(R.standard_normal(n), 3000) * np.exp(-t * 45) + np.sin(2 * np.pi * 120 * t) * np.exp(-t * 25) * 0.6
    return fade_edges(x * 0.9, 0.0005)


def s_impact():
    n = int(SR * 2.5)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * np.cumsum(38 + 80 * np.exp(-t * 12)) / SR) * np.exp(-t * 2.2)
    body = lp(R.standard_normal(n), 1800) * np.exp(-t * 9)
    return fade_edges(np.tanh(s * 2.0 + body * 0.8) * 0.9, 0.0005, 0.2)


def s_win():  # sfx.gd win: 72 76 79 84 79 84, then a 72 76 79 88 chord
    b = buf(1.6)
    for i, m in enumerate([72, 76, 79, 84, 79, 84]):
        gd_tone(b, i * 0.1, 0.16, midi(m), midi(m), 0.22, "square", 8.0, 0.3)
    for m in [72, 76, 79, 88]:
        gd_tone(b, 0.62, 0.98, midi(m), midi(m), 0.12, "tri", 2.5, 1.0, 5.0, 0.004)
    return b


RISER_LEN = BAR


def s_riser():
    return riser(RISER_LEN, 300, 9000) * 0.8


def s_tick():
    return tick() * 1.2


def s_cash():  # ka-ching: drawer clunk, then a bright bell pair
    b = buf(1.0)
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    b[:n] += bp(R.standard_normal(n), 400, 3000) * np.exp(-t * 60) * 0.6
    b[:n] += np.sin(2 * np.pi * 180 * t) * np.exp(-t * 50) * 0.4
    for st_, f in [(0.05, 2093.0), (0.11, 2637.0)]:
        m = len(b) - int(st_ * SR)
        tt = np.arange(m) / SR
        ring = sum(np.sin(2 * np.pi * f * k * tt) * a * np.exp(-tt * d) for k, a, d in [(1, 0.5, 5), (2.76, 0.2, 9), (5.4, 0.1, 14)])
        b[int(st_ * SR):] += ring * (0.8 + 0.2 * np.sin(2 * np.pi * 14 * tt)) * np.minimum(tt / 0.002, 1)
    return b * 0.7


def s_laugh():
    """A few kids giggling: glottal pulses through 'ah' formants, breathy 'h' onsets, falling pitch."""
    out = np.zeros(int(SR * 1.1))
    for f0, off, g, pan in [(330, 0.0, 1.0, 0), (270, 0.035, 0.75, 0), (410, 0.07, 0.55, 0)]:
        for k in range(5):
            st_ = off + k * 0.135
            dur = 0.1
            n = int(dur * SR)
            t = np.arange(n) / SR
            f = f0 * (1 - 0.035 * k) * (1.12 - 0.12 * t / dur)
            src = osc("saw", f, n) + 0.25 * R.standard_normal(n)
            v = bp(src, 650, 1100) * 1.0 + bp(src, 1100, 1500) * 0.6 + bp(src, 2400, 3000) * 0.3
            e = np.clip(t / 0.012, 0, 1) * np.clip((dur - t) / 0.03, 0, 1)
            h = bp(R.standard_normal(int(0.025 * SR)), 1000, 5000) * 0.25
            i = int(st_ * SR)
            out[i:i + len(h)] += h * g * (1 - 0.12 * k)
            i2 = i + len(h) // 2
            out[i2:i2 + n] += v * e * g * (1 - 0.12 * k)
    return out * 0.8


SFX = {
    "bell": s_bell, "blip": s_blip, "pop": s_pop, "ping": s_ping, "star": s_star, "whoosh": s_whoosh,
    "stamp": s_stamp, "shuffle": s_shuffle, "psst": s_psst, "spotted": s_spotted, "whir": s_whir,
    "siren": s_siren, "click": s_click, "crash": s_crash, "paper": s_paper, "spray": s_spray,
    "slap": s_slap, "impact": s_impact, "win": s_win, "riser": s_riser, "tick": s_tick, "cash": s_cash,
    "laugh": s_laugh,
}
# Level of each sound at gain 1.0 (dB, after peak-normalizing the recipe). SFX sit under the music's leads;
# only the big impacts (impact, crash, stamp) are allowed to punch above.
LEVEL = {
    "impact": -2, "crash": -4, "stamp": -5, "slap": -8, "bell": -10, "siren": -16, "riser": -12, "whoosh": -10,
    "spotted": -11, "win": -11, "cash": -12, "laugh": -12, "star": -12, "ping": -12, "pop": -11, "blip": -12,
    "click": -11, "tick": -12, "paper": -10, "spray": -14, "shuffle": -12, "psst": -12, "whir": -13,
}
# Where the moment of each sound sits inside it (seconds). Others: detected onset.
LEAD_IN = {"whoosh": 0.25, "paper": PAPER_THROW, "riser": RISER_LEN}


def onset(x):
    a = np.abs(x) if x.ndim == 1 else np.abs(x).max(1)
    a = uniform_filter1d(a, 32)
    return int(np.argmax(a >= 0.3 * a.max()))


DEMO_CUES = [
    ["tick", 0, 2, 0.8], ["blip", 0, 3, 0.8], ["psst", 1, 1, 0.8], ["pop", 1, 2, 0.8], ["pop", 1, 2.5, 0.8],
    ["spotted", 2, 2, 0.8], ["whir", 3, 0, 0.7], ["siren", 3, 1, 0.6], ["stamp", 4, 0, 0.8], ["whoosh", 5, 0, 0.8],
    ["shuffle", 5, 2, 0.7], ["ping", 6, 1, 0.8], ["star", 6, 3, 0.8], ["click", 7, 1, 0.8], ["blip", 8, 1, 0.8],
    ["spotted", 8, 1, 0.9], ["crash", 10, 0, 0.8], ["paper", 10, 2, 0.8], ["spray", 11, 0, 0.7],
    ["slap", 11, 2, 0.8], ["laugh", 12, 0, 0.8], ["cash", 12, 2, 0.8], ["ping", 13, 0, 0.8],
    ["pop", 14, 0, 0.7], ["pop", 14, 0.5, 0.7], ["pop", 14, 1, 0.7], ["star", 15, 0, 0.8], ["riser", 18, 0, 0.7],
    ["impact", 18, 0, 0.8], ["win", 20, 0, 0.8], ["cash", 21, 0, 0.7], ["impact", 22, 0, 1.0], ["bell", 22, 0, 0.8],
    ["bell", 0, 0, 0.8], ["tick", 23, 1, 0.8], ["nonsense", 3, 0, 1.0],
]


def load_cues():
    if DEMO:
        return [("demo", c) for c in DEMO_CUES]
    cues = []
    for f in sorted((ROOT / "src/steam/sfx").glob("*.json")):
        try:
            data = json.loads(f.read_text() or "[]")
        except (json.JSONDecodeError, OSError) as e:
            print(f"  WARN {f.name}: unreadable ({e}), skipped")
            continue
        if not isinstance(data, list):
            print(f"  WARN {f.name}: not a list, skipped")
            continue
        for c in data:
            cues.append((f.stem, c))
    return cues


BIG = {"impact", "crash", "stamp", "slap", "bell"}  # allowed to punch at (or just above) the music


def build_sfx():
    """-> (small, big, log): the two SFX groups, each at its LEVEL x cue gain, transients on the grid."""
    global R
    small, big = np.zeros((N, 2)), np.zeros((N, 2))
    log = []
    placed = 0
    for src, c in load_cues():
        try:
            name, bar, beat, gain = c[0], float(c[1]), float(c[2]), float(c[3]) if len(c) > 3 else 1.0
        except (TypeError, ValueError, IndexError, KeyError):
            print(f"  WARN {src}: bad cue {c!r}, skipped")
            continue
        if name not in SFX:
            print(f"  WARN {src}: unknown sound '{name}' at {bar:g}.{beat:g}, skipped")
            continue
        at = T(bar, beat)
        if at < 0 or at >= DUR:
            print(f"  WARN {src}: '{name}' at {bar:g}.{beat:g} is outside the 45 s, skipped")
            continue
        if any(abs(at - o) < 0.04 for o in OWNED.get(name, [])):
            print(f"  note {src}: '{name}' at {bar:g}.{beat:g} is already in the score, not doubled")
            continue
        R = np.random.default_rng(zlib.crc32(f"{name}:{bar}:{beat}".encode()))
        x = SFX[name]()
        x = x / (np.abs(x).max() + 1e-9) * 10 ** (LEVEL[name] / 20)
        lead = LEAD_IN.get(name)
        lead = onset(x) / SR if lead is None else lead
        pan = {"psst": -0.3, "laugh": 0.2, "whoosh": 0.0}.get(name, 0.0)
        x = stereo(x, pan)
        t0 = at - lead
        for a, b_, fout, _ in SILENCES:  # a sound running into a silence stops at its edge
            if t0 < a - 0.01 and t0 + len(x) / SR > a - fout:
                k = int((a - t0) * SR)
                f = int(fout * SR)
                x = x[:k].copy()
                x[-f:] *= np.linspace(1, 0, f)[:, None]
        place(big if name in BIG else small, t0, x, gain)
        log.append((src, name, bar, beat, at))
        placed += 1
    print(f"  {placed} SFX placed")
    return hp(small, 90), hp(big, 38), log


def short_db(x, win=0.1):
    """Loudness-like level (dB, K-weighted, centered 100 ms window) per sample."""
    p = uniform_filter1d((kweight(x) ** 2).sum(1), int(win * SR))
    return -0.691 + 10 * np.log10(p + 1e-12)


def keyed(sfx, music_db, margin, floor, rel_ms=150.0):
    """Keep an SFX group under the music: at most music + margin dB (never capped below floor)."""
    gdb = np.minimum(0.0, np.maximum(music_db + margin, floor) - short_db(sfx))
    g = 10 ** (gdb / 20)
    B = 64
    nb = (len(g) + B - 1) // B
    gb = np.pad(g, (0, nb * B - len(g)), constant_values=1.0).reshape(nb, B).min(1)
    gb = minimum_filter1d(gb, 5, mode="nearest")
    a = np.exp(-B / (rel_ms / 1000 * SR))
    env = np.empty(nb)
    e = 1.0
    for i in range(nb):
        e = min(gb[i], e + (1 - e) * (1 - a))
        env[i] = e
    gs = uniform_filter1d(np.repeat(env, B)[: len(g)], 4 * B)
    return sfx * gs[:, None], gs


# ================================================================ mix + master
def make_ir(rt60=1.9, length=2.8, seed=5, predelay=0.018, damp=5000):
    r = np.random.default_rng(seed)
    n = int(length * SR)
    t = np.arange(n) / SR
    x = r.standard_normal((n, 2))
    lo = lp(x, damp) * (10 ** (-3 * t / rt60))[:, None]
    hi = hp(x, damp) * (10 ** (-3 * t / (rt60 * 0.35)))[:, None]
    ir = (lo + 0.6 * hi) * np.clip(t / 0.008, 0, 1)[:, None]
    ir = np.vstack([np.zeros((int(predelay * SR), 2)), ir])
    return ir / np.sqrt((ir ** 2).sum(0) / 2)


def reverb(send):
    ir = make_ir()
    out = np.stack([fftconvolve(send[:, c], ir[:, c])[: len(send)] for c in range(2)], 1)
    return lp(hp(out, 220), 8000) * 0.7


def delay(send, time=0.75 * BEAT, fb=0.45, taps=6):
    out = np.zeros_like(send)
    mono = send.mean(1)
    for k in range(1, taps + 1):
        s = int(round(k * time * SR))
        y = lp(hp(mono, 300), 6000 - 600 * k) * fb ** (k - 1)
        l, r = (1.0, 0.35) if k % 2 else (0.35, 1.0)
        out[s:, 0] += y[: len(out) - s] * l
        out[s:, 1] += y[: len(out) - s] * r
    return out


def duck_curve(depth, rel, attack=0.004):
    d = np.ones(N)
    for t0, s in KICKS:
        i = int(t0 * SR)
        n = int(rel * 5 * SR)
        j = min(N, i + n)
        tt = np.arange(j - i) / SR
        c = 1 - depth * s * np.exp(-tt / rel) * np.clip(tt / attack, 0, 1)
        d[i:j] = np.minimum(d[i:j], c)
    return d


# The written silences: (start, end, fade out, fade in). Music is silent inside; SFX cued inside them still play,
# but anything that started earlier (tails, reverb) is cut at the start so the silence stays a silence.
SILENCES = [(T(8, 0.4), T(8, 2), 0.05, 0.003), (T(17, 3.5), T(18), 0.004, 0.001)]


def mute_windows():
    """1 everywhere except the written silences (short fades so nothing clicks)."""
    m = np.ones(N)
    for a, b_, fout, fin in SILENCES:
        ia, ib = int(a * SR), int(b_ * SR)
        m[ia:ib] = 0
        k = int(fout * SR)
        m[ia - k:ia] = np.minimum(m[ia - k:ia], np.linspace(1, 0, k))
        k = int(fin * SR)
        m[ib:ib + k] = np.minimum(m[ib:ib + k], np.linspace(0, 1, k))
    return m[:, None]


def kweight(x):
    def shelf(fs):
        G, Q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
        K_ = np.tan(np.pi * fc / fs)
        Vh = 10 ** (G / 20)
        Vb = Vh ** 0.4996667741545416
        a0 = 1 + K_ / Q + K_ * K_
        return ([(Vh + Vb * K_ / Q + K_ * K_) / a0, 2 * (K_ * K_ - Vh) / a0, (Vh - Vb * K_ / Q + K_ * K_) / a0],
                [1, 2 * (K_ * K_ - 1) / a0, (1 - K_ / Q + K_ * K_) / a0])

    def highpass(fs):
        Q, fc = 0.5003270373238773, 38.13547087602444
        K_ = np.tan(np.pi * fc / fs)
        a0 = 1 + K_ / Q + K_ * K_
        return [1, -2, 1], [1, 2 * (K_ * K_ - 1) / a0, (1 - K_ / Q + K_ * K_) / a0]

    b1, a1 = shelf(SR)
    b2, a2 = highpass(SR)
    return lfilter(b2, a2, lfilter(b1, a1, x, axis=0), axis=0)


def lufs(x):
    """ITU-R BS.1770-4 integrated loudness (gated)."""
    p = (kweight(x) ** 2).sum(1)
    blk, hop = int(0.4 * SR), int(0.1 * SR)
    cs = np.concatenate([[0], np.cumsum(p)])
    st_ = np.arange(0, len(p) - blk + 1, hop)
    z = (cs[st_ + blk] - cs[st_]) / blk
    lv = -0.691 + 10 * np.log10(z + 1e-20)
    z1 = z[lv > -70]
    if not len(z1):
        return -np.inf
    rel = -0.691 + 10 * np.log10(z1.mean()) - 10
    z2 = z[(lv > -70) & (lv > rel)]
    return -0.691 + 10 * np.log10(z2.mean())


def per_beat(x):
    p = (kweight(x) ** 2).sum(1)
    out = np.zeros((BARS, 4))
    for bar in range(BARS):
        for bb in range(4):
            a, b_ = int(T(bar, bb) * SR), int(T(bar, bb + 1) * SR)
            out[bar, bb] = -0.691 + 10 * np.log10(p[a:b_].mean() + 1e-20)
    return out


def true_peak(x):
    up = resample_poly(x, 4, 1, axis=0)
    return 20 * np.log10(np.abs(up).max() + 1e-12)


def limiter(x, ceiling_db=CEILING_DBTP, look_ms=4.0, rel_ms=90.0):
    """Look-ahead true-peak limiter (4x oversampled detector, smooth gain, no clipping)."""
    c = 10 ** (ceiling_db / 20)
    n = len(x)
    up = np.abs(resample_poly(x, 4, 1, axis=0)).max(1)[: 4 * n]
    pk = np.maximum(up.reshape(n, 4).max(1), np.abs(x).max(1))
    g = np.minimum(1.0, c / np.maximum(pk, 1e-9))
    B = 32
    nb = (n + B - 1) // B
    gb = np.pad(g, (0, nb * B - n), constant_values=1.0).reshape(nb, B).min(1)
    k = int(look_ms / 1000 * SR / B) + 1
    gm = minimum_filter1d(gb, size=2 * k + 1, mode="nearest")
    a = np.exp(-B / (rel_ms / 1000 * SR))
    env = np.empty(nb)
    e = 1.0
    for i in range(nb):
        e = min(gm[i], e + (1 - e) * (1 - a))
        env[i] = e
    gs = np.repeat(env, B)[:n]
    gs = uniform_filter1d(gs, size=k * B, mode="nearest")
    y = x * gs[:, None]
    return np.clip(y, -c, c), gs


def shelf(x, fc, gain_db, kind="low", q=0.707):
    """RBJ shelving EQ."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * fc / SR
    c, al = np.cos(w0), np.sin(w0) / (2 * q)
    sq = 2 * np.sqrt(A) * al
    if kind == "low":
        b = [A * ((A + 1) - (A - 1) * c + sq), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sq)]
        a = [(A + 1) + (A - 1) * c + sq, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sq]
    else:
        b = [A * ((A + 1) + (A - 1) * c + sq), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sq)]
        a = [(A + 1) - (A - 1) * c + sq, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sq]
    return lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def mono_low(x, fc=140):
    m = (x[:, 0] + x[:, 1]) / 2
    s = hp((x[:, 0] - x[:, 1]) / 2, fc)
    return np.stack([m + s, m - s], 1)


def prep(x):
    return mono_low(hp(x[:END], 34, order=4))


def master(x, target=TARGET_LUFS):
    """x already prep()ed -> (mastered, gain applied before the limiter, max gain reduction dB)."""
    fade = int(1.2 * SR)
    g = 10 ** ((target - lufs(x)) / 20)
    for _ in range(4):
        y, gs = limiter(x * g)
        y[-fade:] *= (np.linspace(1, 0, fade) ** 1.6)[:, None]
        L = lufs(y)
        if abs(L - target) < 0.05:
            break
        g *= 10 ** ((target - L) / 20)
    tp = true_peak(y)
    if tp > CEILING_DBTP + 0.2:  # belt and braces
        y *= 10 ** ((CEILING_DBTP - tp) / 20)
    return y, g, gs


def write(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    r = np.random.default_rng(1)
    d = (r.random(x.shape) - r.random(x.shape)) / 32768  # TPDF dither
    y = np.round(np.clip(x + d, -1, 32767 / 32768) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(y.tobytes())
    print(f"  wrote {path.relative_to(ROOT)}  {len(x) / SR:.3f} s  {len(x)} frames")


def report(name, x, gs=None):
    L, tp = lufs(x), true_peak(x)
    print(f"\n{name}: {L:.1f} LUFS integrated, true peak {tp:.2f} dBTP, sample peak "
          f"{20 * np.log10(np.abs(x).max() + 1e-12):.2f} dBFS, duration {len(x) / SR:.3f} s")
    if gs is not None:
        gr = -20 * np.log10(gs)
        i = int(np.argmax(gr))
        busy = gr[int(T(4) * SR):int(T(22) * SR)]
        print(f"  limiter: max {gr[i]:.1f} dB at bar {i / SR / BAR:.2f}; bars 4-22 median {np.median(busy):.1f} dB, "
              f"95th pct {np.percentile(busy, 95):.1f} dB")
    pb = per_beat(x)
    print("  bar  " + "  ".join(f"b{i}  " for i in range(4)) + "  section")
    names = {}
    for s in TL["sections"]:
        names[s["from"]] = s["act"]
    for bar in range(BARS):
        row = " ".join(f"{v:6.1f}" if v > -60 else "   -- " for v in pb[bar])
        bar_ = "#" * max(0, int((pb[bar].mean() + 40) / 1.5))
        print(f"  {bar:>3}  {row}  {names.get(bar, ''):<7}{bar_}")
    return pb


def seg(x, a, b_):
    p = (kweight(x) ** 2).sum(1)[int(a * SR):int(b_ * SR)]
    return -0.691 + 10 * np.log10(p.mean() + 1e-20)


def checks(x):
    S = lambda a, b_: seg(x, T(*a), T(*b_))  # noqa: E731
    tests = [
        ("drop 1 (4) louder than tense 2-3", S((4, 0), (5, 0)) > S((2, 0), (4, 0)) + 4),
        ("drop 2 (18-19) is the loudest section", S((18, 0), (20, 0)) >= max(S((b_, 0), (b_ + 2, 0)) for b_ in range(0, 22, 2) if b_ != 18) - 0.3),
        ("drop 2 louder than build 16-17", S((18, 0), (20, 0)) > S((16, 0), (17, 3.5)) + 1.5),
        ("groove A (6-9) quieter than groove B (10-13)", S((6, 0), (10, 0)) < S((10, 0), (14, 0)) - 2),
        ("hush (bar 1) quiet", S((1, 0), (2, 0)) < S((4, 0), (6, 0)) - 12),
        ("stop-time 8.0.5-8.2 silent (< -45)", S((8, 0.6), (8, 1.95)) < -45),
        ("half-beat 17.3.5-18.0 silent (< -60)", S((17, 3.52), (17, 3.99)) < -60),
        ("slam 22.0 louder than ring-out 23", S((22, 0), (22, 1)) > S((23, 0), (24, 0)) + 6),
    ]
    print()
    for name, ok in tests:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")


def main():
    print("building score...")
    build_music()
    # sidechain: the bass gets out of the kick's way; everything tonal breathes with it
    BUS["bass"] *= duck_curve(0.75, 0.06)[:, None]
    tonal = duck_curve(0.4, 0.09)[:, None]
    for k in ("keys", "lead", "fx"):
        BUS[k] *= tonal
    BUS["bass"] = lp(hp(BUS["bass"], 30), 3000)
    BUS["drums"] = np.tanh(BUS["drums"] * 1.2) / 1.2
    rev = reverb(REV) * tonal
    dly = delay(DLY) * tonal * 0.8
    MIXG = {"kick": 1.0, "drums": 1.2, "bass": 1.0, "keys": 1.6, "lead": 1.8, "fx": 1.0}
    music = sum(BUS[k] * g for k, g in MIXG.items()) + rev + dly
    music = shelf(shelf(music, 60, -4.5, "low"), 4500, 2.5, "high")  # tame the sub, open the top
    mute = mute_windows()
    music = prep(music) * mute[:END]  # after every filter, so the written silences stay silent
    # the music sets the scale: normalized to the target, the SFX LEVELs are relative to that
    music *= 10 ** ((TARGET_LUFS - lufs(music)) / 20)
    print("placing SFX...")
    small, big, log = build_sfx()
    mdb = short_db(music)
    small, g_small = keyed(prep(small + reverb(small * 0.3) * mute), mdb, -7.0, -24.0)
    big, g_big = keyed(prep(big + reverb(big * 0.3) * mute), mdb, 1.0, -16.0)
    sfx = small + big
    if log:
        print(f"  SFX kept under the music: small group turned down up to {-20 * np.log10(g_small.min()):.1f} dB, "
              f"big group up to {-20 * np.log10(g_big.min()):.1f} dB")
    out = ROOT / ("out/steam/audio-demo" if DEMO else "public/audio/steam")
    m, _, gr_m = master(music)
    mix, g, gr_x = master(music + sfx)
    s = sfx * g
    tp = true_peak(s)
    if tp > CEILING_DBTP:
        s *= 10 ** ((CEILING_DBTP - tp) / 20)
    write(out / "music.wav", m)
    write(out / "sfx.wav", s)
    write(out / "mix.wav", mix)
    report("music.wav", m, gr_m)
    checks(m)
    report("mix.wav", mix, gr_x)
    print(f"\nsfx.wav: true peak {true_peak(s):.2f} dBTP")
    if log:
        print("\nEach SFX against the music under it (LUFS over 300 ms from the hit; last column = SFX minus music):")
        for src, name, bar, beat, at in log:
            a, b_ = at, at + 0.3
            ls, lm = seg(sfx, a, b_), seg(music, a, b_)
            print(f"  {src:<7}{name:<8}{bar:>5g}.{beat:<6g} sfx {ls:6.1f}  music {lm:6.1f}  {ls - lm:+6.1f}"
                  + ("  (big)" if name in BIG else ""))


if __name__ == "__main__":
    main()
