"""Bunk Master launch trailer: original score + SFX, synthesized from scratch (no samples).

128 BPM, A minor, the game's own chase progression (Am-F-G-E, autoload/sfx.gd) and its SFX
recipes (bell, spotted alarm, pickup, win arpeggio). Timings come from src/launch/timeline.json,
the same file the visuals read, so every hit lands on its frame.

Run from videos/:  uv run --with numpy --with scipy python audio/launch_music.py
Writes public/audio/launch/{music,sfx,mix}.wav (44.1 kHz stereo).
"""
import json
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

ROOT = Path(__file__).resolve().parent.parent
TL = json.loads((ROOT / "src/launch/timeline.json").read_text())
SR = 44100
BPM = TL["bpm"]
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = TL["bars"]
DUR = BARS * BAR
N = int(round(DUR * SR)) + SR * 2  # tail room, trimmed at the end
rng = np.random.default_rng(7)


def T(bar, beat=0.0):
    return (bar * 4 + beat) * BEAT


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def buf():
    return np.zeros((N, 2))


def env_adsr(n, a=0.005, d=0.1, s=0.6, r=0.05, hold=None):
    t = np.arange(n) / SR
    hold = n / SR if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip((t - hold) / max(r, 1e-6), 0, 1)
    return e * (1 - rel)


def osc(kind, f, n, phase0=0.0, duty=0.5):
    f = np.broadcast_to(np.asarray(f, float), (n,))
    ph = phase0 + np.cumsum(f) / SR
    x = ph % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    if kind == "square":
        return np.where(x < duty, 1.0, -1.0)
    if kind == "tri":
        return 4 * np.abs(x - 0.5) - 1
    if kind == "saw":
        return 2 * x - 1
    raise ValueError(kind)


def lp(x, fc, order=2):
    sos = butter(order, min(fc, SR * 0.45), "low", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def hp(x, fc, order=2):
    sos = butter(order, fc, "high", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def add(dst, start, x, gain=1.0, pan=0.0):
    i = int(round(start * SR))
    if i >= N:
        return
    if x.ndim == 1:
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        x = np.stack([x * l, x * r], 1) * np.sqrt(2)
    j = min(N, i + len(x))
    if i < 0:
        x = x[-i:]
        i = 0
    dst[i:j] += x[: j - i] * gain


def noise(n):
    return rng.standard_normal(n)


# ---------------------------------------------------------------- drums
def kick(big=False):
    n = int(SR * (0.55 if big else 0.32))
    t = np.arange(n) / SR
    f = 42 + (160 if big else 130) * np.exp(-t * 28)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * (5 if big else 9))
    x += 0.35 * lp(noise(n), 3000) * np.exp(-t * 180)
    return np.tanh(x * (2.2 if big else 1.6)) * 0.9


def clap():
    n = int(SR * 0.25)
    t = np.arange(n) / SR
    e = np.zeros(n)
    for k, off in enumerate([0, 0.011, 0.022]):
        i = int(off * SR)
        e[i:] += np.exp(-(t[: n - i]) * (160 if k < 2 else 22))
    return bp(noise(n), 900, 5200) * e * 0.8


def hat(open_=False):
    n = int(SR * (0.22 if open_ else 0.045))
    t = np.arange(n) / SR
    return hp(noise(n), 7500) * np.exp(-t * (14 if open_ else 90)) * 0.5


def snare():
    n = int(SR * 0.2)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    return (0.6 * body + bp(noise(n), 1500, 9000) * np.exp(-t * 24)) * 0.7


def crash(length=2.2):
    n = int(SR * length)
    t = np.arange(n) / SR
    x = hp(noise(n), 4000) * np.exp(-t * 2.2)
    return np.stack([x, hp(noise(n), 4000) * np.exp(-t * 2.2)], 1) * 0.35


def woodblock(f):
    n = int(SR * 0.08)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * f * t) * np.exp(-t * 60) * 0.6


# ---------------------------------------------------------------- synth voices
def pluck(kind, f, dur, cutoff=4000, duty=0.5, decay=6.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    x = osc(kind, f, n, duty=duty) * np.exp(-t * decay) * np.clip(t / 0.003, 0, 1)
    x *= np.clip((dur - t) / 0.01, 0, 1)
    return lp(x, cutoff)


def pad(freqs, dur, cutoff=1800):
    n = int(SR * dur)
    out = np.zeros((n, 2))
    for f in freqs:
        for det, pan in [(-0.12, -0.7), (0.0, 0.0), (0.12, 0.7)]:
            x = osc("saw", f * 2 ** (det / 12), n, phase0=rng.random())
            l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            out[:, 0] += x * l
            out[:, 1] += x * r
    out = lp(out, cutoff) / (len(freqs) * 3)
    return out * env_adsr(n, a=0.08, d=0.4, s=0.8, r=0.3, hold=dur - 0.3)[:, None]


def bass808(f, dur, glide_from=None):
    n = int(SR * dur)
    t = np.arange(n) / SR
    ff = np.full(n, f)
    if glide_from:
        ff = f + (glide_from - f) * np.exp(-t * 18)
    x = np.sin(2 * np.pi * np.cumsum(ff) / SR)
    x = np.tanh(x * 2.5) * np.exp(-t * 1.2) * np.clip((dur - t) / 0.03, 0, 1)
    return x * 0.7


CH = {
    "Am": (45, [57, 60, 64]), "F": (41, [53, 57, 60]), "G": (43, [55, 59, 62]),
    "E": (40, [52, 56, 59]), "C": (48, [55, 60, 64]), "A": (45, [57, 61, 64]),
}
# One chord per bar; bar 11 splits G | E. Bars 14-15 end in A major (the "win" lift).
PROG = ["Am", "Am", "Am", "F", "G", "E", "Am", "F", "G", "E", "Am", ("G", "E"), "F", "G", "A", "A"]


def chord_at(bar, beat):
    c = PROG[bar]
    if isinstance(c, tuple):
        c = c[0] if beat < 2 else c[1]
    return CH[c]


music = buf()
drums = buf()
kicks = []  # for sidechain

# ---- bar 0-1: the classroom clock ticks, pad breathes, arp creeps in
for beat in range(8):
    add(drums, T(0, beat), woodblock(1900 if beat % 2 == 0 else 1500), 0.35, pan=0.3 if beat % 2 else -0.3)
add(music, T(0), pad([midi(m) for m in CH["Am"][1]], BAR * 2, cutoff=900), 0.5)

# ---- arps (16ths over chord tones), the game's chase texture
def arp_bar(bar, gain, cutoff, octave=12, beats=range(4)):
    for beat in beats:
        for s in range(4):
            root, tones = chord_at(bar, beat)
            seq = tones + [tones[0] + 12]
            m = seq[(beat * 4 + s) % 4] + octave
            add(music, T(bar, beat + s / 4), pluck("square", midi(m), BEAT / 4 * 0.9, cutoff=cutoff, duty=0.25, decay=10),
                gain, pan=-0.25 if s % 2 else 0.25)

for bar in [1]:
    arp_bar(bar, 0.10, 1400)
for bar in [2, 3, 5, 6, 7, 8, 9]:
    arp_bar(bar, 0.12, 3200)
for bar in [10, 11]:
    arp_bar(bar, 0.13, 5200)
for bar in [12, 13]:
    arp_bar(bar, 0.12, 4200)

# ---- riser into bar 2
def riser(start, dur, gain=0.3, f0=300, f1=6000):
    n = int(SR * dur)
    t = np.arange(n) / SR
    u = t / dur
    x = noise(n)
    out = np.zeros(n)
    # swept band: filter in chunks
    chunks = 24
    for k in range(chunks):
        a, b_ = k * n // chunks, (k + 1) * n // chunks
        fc = f0 * (f1 / f0) ** (k / chunks)
        out[a:b_] = bp(x[a:b_], fc * 0.7, fc * 1.4)
    add(music, start, out * u ** 2 * gain)

riser(T(1), BAR, 0.25)

# ---- groove A: bars 2-3, 5 (4 is the break)
def groove(bar, kick_pat, clap_beats=(1, 3), hats=8, big=False, open_hat=False):
    for kb in kick_pat:
        add(drums, T(bar, kb), kick(big), 0.9)
        kicks.append(T(bar, kb))
    for cb in clap_beats:
        add(drums, T(bar, cb), clap(), 0.55, pan=0.05)
    for h in range(hats):
        step = 4 / hats
        add(drums, T(bar, h * step), hat(), 0.35 if h % 2 else 0.22, pan=0.4)
    if open_hat:
        for ob in (0.5, 1.5, 2.5, 3.5):
            add(drums, T(bar, ob), hat(True), 0.18, pan=-0.3)


for bar in [2, 3]:
    groove(bar, (0, 1.5, 2, 3.25) if bar == 3 else (0, 1.5, 2), hats=8)
# bar 4: one hit, then the room goes quiet ("Who's talking?!")
add(drums, T(4), kick(True), 1.0)
kicks.append(T(4))
add(drums, T(4), crash(1.2), 0.5)
groove(5, (0, 1.5, 2, 2.75), hats=16)
for bar in [6, 7, 8]:
    groove(bar, (0, 1.5, 2, 3.25), hats=16, open_hat=True)
# bar 9: build: kick on every beat, snare roll 8ths -> 16ths -> 32nds, stop half a beat before the drop
for kb in range(4):
    add(drums, T(9, kb), kick(), 0.8)
    kicks.append(T(9, kb))
for i in range(4):
    add(drums, T(9, i * 0.5), snare(), 0.3 + i * 0.03)
for i in range(8):
    add(drums, T(9, 2 + i * 0.125), snare(), 0.4 + i * 0.03)
riser(T(9), BAR - BEAT * 0.5, 0.4, 400, 9000)
# bars 10-11: DROP
for bar in [10, 11]:
    groove(bar, (0, 0.75, 1.5, 2.5, 3.25) if bar == 10 else (0, 0.75, 1.5, 2, 2.5, 3), hats=16, big=True, open_hat=True)
    add(drums, T(bar), crash(), 0.6)
# bars 12-13: lift (half-time, bright)
for bar in [12, 13]:
    groove(bar, (0, 2.5), clap_beats=(2,), hats=8, open_hat=True)
    add(drums, T(bar), crash(1.6), 0.35)
# bar 14: logo slam, then ring-out
add(drums, T(14), kick(True), 1.0)
kicks.append(T(14))
add(drums, T(14), crash(3.5), 0.7)
add(drums, T(15), kick(), 0.6)
kicks.append(T(15))

# ---- bass
def square_bass(bar, pattern, gain=0.28):
    for bb, octv, length in pattern:
        root, _ = chord_at(bar, bb)
        add(music, T(bar, bb), pluck("square", midi(root + octv), BEAT * length, cutoff=900, duty=0.125, decay=3), gain)

for bar in [2, 3, 5, 6, 7, 8, 9]:
    square_bass(bar, [(0, 0, 0.45), (0.5, 12, 0.4), (1, 0, 0.45), (1.5, 12, 0.4), (2, 0, 0.45), (2.5, 12, 0.4), (3, 0, 0.45), (3.5, 12, 0.4)])
for bar in [10, 11]:
    for bb, length in [(0, 0.7), (0.75, 0.7), (1.5, 1.0), (2.5, 0.7), (3.25, 0.7)]:
        root, _ = chord_at(bar, bb)
        add(music, T(bar, bb), bass808(midi(root - 12 + 12), BEAT * length, glide_from=midi(root + 12) if bb == 0 else None), 0.55)
for bar in [12, 13]:
    root, _ = chord_at(bar, 0)
    add(music, T(bar), bass808(midi(root), BEAT * 2.4), 0.45)
    add(music, T(bar, 2.5), bass808(midi(root), BEAT * 1.4), 0.4)
add(music, T(14), bass808(midi(33), BAR * 1.6, glide_from=midi(45)), 0.6)

# ---- pads
for bar in range(2, 16):
    if bar == 4:
        continue
    root, tones = chord_at(bar, 0)
    if isinstance(PROG[bar], tuple):
        for half in range(2):
            _, tn = chord_at(bar, half * 2)
            add(music, T(bar, half * 2), pad([midi(m) for m in tn], BEAT * 2, cutoff=1600), 0.3)
        continue
    add(music, T(bar), pad([midi(m) for m in tones], BAR if bar < 14 else BAR * (2 if bar == 14 else 1.4),
                           cutoff=2400 if bar >= 10 else 1500), 0.32 if bar >= 10 else 0.26)

# ---- lead hook (square + saw layer), bars 6-8 and the drop
HOOK = [  # (beat, midi, beats) over a bar; A minor, chord tones on the downbeats
    [(0, 76, 0.5), (0.75, 72, 0.25), (1, 74, 0.5), (1.5, 76, 0.5), (2.5, 79, 0.5), (3, 76, 0.75)],   # Am
    [(0, 77, 0.5), (0.75, 76, 0.25), (1, 72, 0.5), (1.5, 69, 0.5), (2.5, 72, 0.5), (3, 74, 0.75)],   # F
    [(0, 79, 0.5), (0.75, 78, 0.25), (1, 79, 0.5), (1.5, 81, 0.5), (2.5, 83, 0.5), (3, 79, 0.75)],   # G
    [(0, 80, 0.75), (1, 76, 0.5), (1.5, 80, 0.5), (2, 83, 1.0), (3.25, 80, 0.25), (3.5, 83, 0.5)],   # E
]

def lead(bar, phrase, gain=0.12, octave=0):
    for bb, m, ln in phrase:
        f = midi(m + octave)
        n = int(SR * BEAT * ln)
        t = np.arange(n) / SR
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) / 0.1, 0, 1)
        x = 0.6 * osc("square", f * vib, n, duty=0.5) + 0.4 * osc("saw", f * 1.003 * vib, n)
        x = lp(x * env_adsr(n, a=0.004, d=0.15, s=0.7, r=0.03, hold=n / SR - 0.03), 3800)
        add(music, T(bar, bb), x, gain, pan=0.1)
        add(music, T(bar, bb) + BEAT * 0.75, x, gain * 0.3, pan=-0.6)  # dotted-8th echo

lead(6, HOOK[0])
lead(7, HOOK[1])
lead(8, HOOK[2])
lead(10, HOOK[0], 0.14)
lead(10, HOOK[0], 0.07, -12)
lead(11, [(0, 79, 0.5), (0.75, 78, 0.25), (1, 79, 0.5), (1.5, 81, 0.5), (2, 80, 0.75), (3, 83, 0.5), (3.5, 80, 0.5)], 0.14)
lead(11, [(0, 79, 0.5), (0.75, 78, 0.25), (1, 79, 0.5), (1.5, 81, 0.5), (2, 80, 0.75), (3, 83, 0.5), (3.5, 80, 0.5)], 0.07, -12)
# lift melody: bright, the game's win notes (72 76 79 84) stretched out
lead(12, [(0, 81, 1.0), (1, 84, 0.5), (1.5, 81, 0.5), (2, 77, 1.5), (3.5, 79, 0.5)], 0.12)
lead(13, [(0, 79, 0.75), (1, 83, 0.5), (1.5, 86, 1.0), (2.75, 83, 0.25), (3, 86, 1.0)], 0.12)
lead(14, [(0, 88, 1.5), (2, 85, 0.5), (2.5, 81, 1.5)], 0.1)
lead(15, [(0, 81, 3.5)], 0.08)

# ---- sidechain: duck music under every kick
duck = np.ones(N)
for k in kicks:
    i = int(k * SR)
    n = int(0.22 * SR)
    j = min(N, i + n)
    curve = 1 - 0.55 * np.exp(-np.arange(j - i) / SR * 14)
    duck[i:j] = np.minimum(duck[i:j], curve)
music *= duck[:, None]

# ---- bar 4.1-4.3: the break. Everything but SFX fades out and back
brk = np.ones(N)
a, b_ = int(T(4, 0.6) * SR), int(T(5) * SR)
brk[a:b_] = 0.0
ramp = int(0.04 * SR)
brk[a - ramp:a] = np.linspace(1, 0, ramp)
music *= brk[:, None]
# bar 9.3.5: half a beat of silence before the drop
a, b_ = int(T(9, 3.5) * SR), int(T(10) * SR)
music[a:b_] *= 0.05
drums[a:b_] *= 0.0

# ---------------------------------------------------------------- SFX (recipes from autoload/sfx.gd)
def tone(dur, f0, f1, amp, wave_="sine", decay=0.0, vib_hz=0, vib=0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = f0 + (f1 - f0) * t / dur
    if vib_hz:
        f = f * (1 + vib * np.sin(2 * np.pi * vib_hz * t))
    x = osc(wave_, f, n) * amp
    if decay:
        x *= np.exp(-t * decay)
    return x * np.clip((dur - t) / 0.01, 0, 1)


def s_bell():
    dur = 2.5
    n = int(SR * dur)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for mul, a in [(1, 1), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12)]:
        x += a * np.sin(2 * np.pi * 1100 * mul * t) * np.exp(-t * (1.6 * mul ** 0.5))
    clapper = 0.6 + 0.4 * (np.sin(2 * np.pi * 22 * t) > 0)
    return x * clapper * np.clip(t / 0.002, 0, 1) * 0.35 * np.exp(-t * 0.4)


def s_blip():
    return tone(0.07, 880, 880, 0.35, "square", decay=30) * 0.6


def s_pop():
    return tone(0.09, 500, 1400, 0.6, "sine", decay=25)


def s_ping():  # pickup: 1318.5 then 1975.5 triangle
    return np.concatenate([tone(0.07, 1318.5, 1318.5, 0.5, "tri", decay=8), tone(0.16, 1975.5, 1975.5, 0.5, "tri", decay=14)])


def s_star():
    x = np.concatenate([tone(0.06, 1318.5, 1318.5, 0.5, "tri"), tone(0.06, 1568, 1568, 0.5, "tri"), tone(0.3, 2637, 2637, 0.5, "tri", decay=9)])
    return x


def s_whoosh(dur=0.45):
    n = int(SR * dur)
    t = np.arange(n) / SR
    u = t / dur
    x = noise(n)
    out = np.zeros(n)
    for k in range(16):
        a, b_ = k * n // 16, (k + 1) * n // 16
        fc = 600 * (8 ** (k / 16))
        out[a:b_] = bp(x[a:b_], fc * 0.6, fc * 1.6)
    return out * np.sin(np.pi * u) ** 2 * 0.8


def s_stamp():
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(60 + 120 * np.exp(-t * 40)) / SR) * np.exp(-t * 10)
    slap = bp(noise(n), 300, 4000) * np.exp(-t * 45)
    return np.tanh((thump * 1.2 + slap * 0.8) * 1.5) * 0.8


def s_shuffle():
    out = np.zeros(int(SR * 0.5))
    for k in range(7):
        c = bp(noise(int(SR * 0.04)), 1500, 6000) * np.exp(-np.arange(int(SR * 0.04)) / SR * 90)
        i = int(k * 0.058 * SR)
        out[i:i + len(c)] += c * (0.5 + 0.1 * k)
    return out * 0.6


def s_psst():
    n = int(SR * 0.4)
    t = np.arange(n) / SR
    return bp(noise(n), 3000, 9000) * np.clip(t / 0.04, 0, 1) * np.exp(-t * 6) * 0.7


def s_spotted():  # 520 -> 1300 Hz, then 1568 Hz
    return np.concatenate([tone(0.18, 520, 1300, 0.45, "square"), tone(0.35, 1568, 1568, 0.45, "square", decay=5)]) * 0.6


def s_whir():
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    x = lp(osc("saw", 90 + 30 * np.sin(2 * np.pi * 3 * t), n), 1200) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * t))
    return x * np.sin(np.pi * t / 0.6) * 0.5


def s_siren(dur=1.2):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 850 + 250 * np.sin(2 * np.pi * t / 0.6 - np.pi / 2)
    return lp(osc("saw", f, n), 3000) * 0.3 * np.clip(t / 0.05, 0, 1) * np.clip((dur - t) / 0.2, 0, 1)


def s_click():
    n = int(SR * 0.06)
    t = np.arange(n) / SR
    return (bp(noise(n), 2000, 8000) * np.exp(-t * 200) + np.sin(2 * np.pi * 2400 * t) * np.exp(-t * 90) * 0.5) * 0.8


def s_crash():  # trolley into staff: thump + metal clang + rattle
    n = int(SR * 1.2)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(50 + 90 * np.exp(-t * 30)) / SR) * np.exp(-t * 8)
    clang = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in [(523, 6), (1187, 7), (1790, 9), (2710, 12)]) * 0.25
    rattle = bp(noise(n), 2000, 9000) * np.exp(-t * 7) * (0.5 + 0.5 * (np.sin(2 * np.pi * 26 * t) > 0))
    return np.tanh(thump * 1.4 + clang + rattle * 0.5) * 0.8


def s_paper():
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    x = bp(noise(n), 1500, 7000) * np.exp(-t * 10)
    crack = (rng.random(n) < 0.004) * rng.standard_normal(n) * 2
    return np.concatenate([s_whoosh(0.3) * 0.5, x * 0.6 + crack * 0.3])


def s_spray():
    n = int(SR * 0.9)
    t = np.arange(n) / SR
    return hp(noise(n), 2500) * np.clip(t / 0.02, 0, 1) * np.exp(-t * 2.5) * 0.55


def s_slap():
    n = int(SR * 0.2)
    t = np.arange(n) / SR
    return (lp(noise(n), 2500) * np.exp(-t * 40) + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 25) * 0.6) * 0.9


def s_impact():
    n = int(SR * 2.5)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * np.cumsum(38 + 80 * np.exp(-t * 12)) / SR) * np.exp(-t * 2.2)
    body = lp(noise(n), 1800) * np.exp(-t * 9)
    return np.tanh(sub * 2.0 + body * 0.8) * 0.9


def s_win():  # MIDI 72 76 79 84 79 84
    return np.concatenate([tone(0.1 if i < 5 else 0.45, midi(m), midi(m), 0.4, "square", decay=4 if i == 5 else 0) for i, m in enumerate([72, 76, 79, 84, 79, 84])]) * 0.7


SFX = {
    "bell": s_bell, "blip": s_blip, "pop": s_pop, "ping": s_ping, "star": s_star, "whoosh": s_whoosh,
    "stamp": s_stamp, "shuffle": s_shuffle, "psst": s_psst, "spotted": s_spotted, "whir": s_whir,
    "siren": s_siren, "click": s_click, "crash": s_crash, "paper": s_paper, "spray": s_spray,
    "slap": s_slap, "impact": s_impact, "win": s_win,
}
# Where the transient sits inside each sound (so the peak, not the file start, lands on the beat).
LEAD_IN = {"whoosh": 0.22, "paper": 0.28, "siren": 0.0}

sfx = buf()
for name, bar, beat, gain in TL["sfx"]:
    x = SFX[name]()
    add(sfx, T(bar, beat) - LEAD_IN.get(name, 0.0), x, gain * 1.1, pan=0.0)

# ---------------------------------------------------------------- reverb + master
def reverb(x, mix=0.18):
    out = np.zeros_like(x)
    for ch in range(2):
        acc = np.zeros(len(x))
        for d, g in [(1557, 0.8), (1617, 0.79), (1491, 0.8), (1422, 0.78)]:
            d += ch * 23
            a = np.zeros(d + 1)
            a[0], a[d] = 1, -g
            acc += lfilter([1.0], a, x[:, ch])
        for d, g in [(225, 0.5), (556, 0.5)]:
            bcoef = np.zeros(d + 1)
            bcoef[0], bcoef[d] = -g, 1
            acoef = np.zeros(d + 1)
            acoef[0], acoef[d] = 1, -g
            acc = lfilter(bcoef, acoef, acc)
        out[:, ch] = acc * 0.06
    return x + lp(out, 5000) * mix / 0.18 * 0.18


music = reverb(music + drums * 0.25, 0.2) + drums * 0.75
sfx = reverb(sfx, 0.15)

end = int(DUR * SR)
fade = int(1.2 * SR)


def master(x, peak=0.89):
    x = x[:end].copy()
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 1.5
    x = np.tanh(x * 1.1)
    return x / (np.abs(x).max() + 1e-9) * peak


def write(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    y = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(y.tobytes())
    print(path.relative_to(ROOT), f"{len(x) / SR:.2f}s")


out = ROOT / "public/audio/launch"
m = master(music, 0.8)
s = master(sfx, 0.8)
write(out / "music.wav", m)
write(out / "sfx.wav", s)
write(out / "mix.wav", master(music * 0.8 + sfx * 0.62))
