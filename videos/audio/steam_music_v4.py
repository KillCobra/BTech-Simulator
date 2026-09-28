"""Bunk Master Steam trailer, score v4: trailer 1's cue (audio/make_music.py) grown into the film, drums up front.

v3's tune and rhythm, unchanged: 128 BPM D-minor chip-pop, i VI III VII (Dm Bb F C), supersaw offbeat stabs, chip
lead with vibrato and a dotted-8th echo, pizz sneak bass, root/octave saw bass, blip arps, the school bell and the
clock. The instruments and the hook are copied verbatim from make_music.py.

v4 makes the drums a feature, still trailer 1's kit: the kick gets a sub layer and a click, the snare is snare +
clap + body with a room, 16th hats with velocity accents and open-hat lifts, ghost snares, a tom fill into every
section change, a crash on section downbeats, rolls into the drops, a breakbeat for SURPRISE TEST and the chase
(DROP 2) with a half-time apex, shaker / tambourine / cowbell in the lift, all glued by parallel compression.

The arrangement is driven by SECTIONS below (one row per section, one chord per bar); starts are cumulative, so
inserting a bar in the film is a one-line change. The rows are checked against timeline.json's act windows.
Current map (global bars, 31 bars = 58.125 s):
  intro 0-1  build 2-3 (RUN! 3.3)  drop1 4-5  sneak 6-7  hit 8 (silence 8.0.4-8.1)  voice 9 (claims on .0 .1 .2)
  talk 10-11  chaos 12-15 (breakbeat 14-15)  canteen 16-17 (half time)  lift 18-19  maps 20-21
  exits 22 (crash zoom 22.3, silence 22.3.5-23.0)  drop2 23-24 (breakbeat, half-time apex 24.0)  escape 25 (win 25.2)
  bell 26-27 (NEW RANK 27.2)  logo 28-29  soon 30, fade over the last 1.2 s

Accents follow the act SFX: every big cue (stamp, impact, slap, crash, star) also gets a musical hit on the
current chord. SFX cues are read from src/steam/sfx/<act>.json in LOCAL bars and shifted by timeline.json
`offsets`; the SFX engine (recipes, placement on the transient, music-keyed levels) is audio/steam_music.py's.

Run from videos/:  uv run --with numpy --with scipy python audio/steam_music_v4.py
Writes public/audio/steam/{music,sfx,mix}.wav: 44.1 kHz stereo, the film's exact length, -14 LUFS, true peak -1.5 dBTP.
"""
import json
import sys
import zlib
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_music as S  # noqa: E402  (SFX recipes, loudness, limiter, writer)

# -1.7 dBTP on our 4x-oversampled meter reads <= -1.5 dBTP on ffmpeg's ebur128 (it interpolates a little higher)
S.CEILING_DBTP = -1.7
S.limiter.__defaults__ = (S.CEILING_DBTP,) + S.limiter.__defaults__[1:]

ROOT = Path(__file__).resolve().parent.parent
TL = json.loads((ROOT / "src/steam/timeline.json").read_text())
SR = 44100
BPM = float(TL["bpm"])
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = TL["bars"]
LENGTH = BARS * BAR  # 58.125 s
N = int(round(LENGTH * SR))
rng = np.random.default_rng(7)
assert S.SR == SR and S.END == N


def T(bar, beat=0.0):
    """Seconds at a 0-based global bar and beat (the film's b(bar, beat))."""
    return (bar * 4 + beat) * BEAT


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


# ============================================================ make_music.py instruments (verbatim)
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


# ============================================================ harmony + the hook (make_music.py, verbatim)
DM, BB, F, C = [62, 65, 69], [58, 62, 65], [57, 60, 65], [55, 60, 64]
PROG = [DM, BB, F, C]
ROOTS = [38, 34, 41, 36]
HOOK = [
    [(0, 2, 74), (3, 1, 77), (4, 2, 81), (6, 2, 79), (8, 2, 77), (10, 1, 76), (11, 1, 77), (12, 4, 74)],
    [(0, 2, 70), (2, 2, 74), (4, 2, 77), (7, 1, 74), (8, 3, 77), (11, 1, 79), (12, 4, 81)],
    [(0, 2, 81), (3, 1, 84), (4, 2, 81), (6, 2, 79), (8, 2, 77), (10, 2, 79), (12, 4, 81)],
    [(0, 2, 79), (2, 2, 76), (4, 2, 72), (6, 2, 76), (8, 2, 79), (10, 2, 84), (12, 2, 81), (14, 2, 79)],
]
S16 = BEAT / 4
SNEAK = [[38, None, 41, None, 43, None, 44, 45], [None, 45, None, 44, 43, None, 41, None]]
TEASER = [74, 77, 81, 79]

# ============================================================ the film, one row per section
# (name, chord per bar: index into PROG). Starts are cumulative: inserting a bar = adding a chord to one row.
SECTIONS = [
    ("intro", [0, 0]),          # bell on 0.0, clock, sneak bass
    ("build", [0, 0]),          # drums in, riser, RUN! on .3.3
    ("drop1", [0, 1]),          # DROP 1
    ("sneak", [0, 0]),          # DODGE
    ("hit", [0]),               # hit, silence to .1, stab, 16th stabs
    ("voice", [0]),             # PROXIMITY VOICE: claims on .0 .1 .2, held to the next bar
    ("talk", [0, 1]),           # TALK YOUR WAY OUT
    ("chaos", [0, 1, 2, 3]),    # CAUSE CHAOS (4/4), SURPRISE TEST (breakbeat)
    ("canteen", [1, 3]),        # items bar, half time
    ("lift", [2, 3]),           # friends: percussion, claps
    ("maps", [0, 1]),           # maps build
    ("exits", [3]),             # exits on 8ths, crash zoom .3, silence .3.5
    ("drop2", [0, 1]),          # DROP 2: breakbeat chase, half-time apex
    ("escape", [2]),            # win arpeggio on .2
    ("bell", [3, 3]),           # FINAL BELL held, NEW RANK on +1.2
    ("logo", [0, 1]),           # logo slam
    ("soon", [0]),              # COMING SOON, ring-out
]
START, CHORD = {}, []
for _name, _chs in SECTIONS:
    START[_name] = len(CHORD)
    CHORD += _chs
assert len(CHORD) == BARS, f"SECTIONS has {len(CHORD)} bars, timeline.json {BARS}"
for _s in TL["sections"]:  # the acts' windows must agree with the rows above
    _row = {"open": "intro", "dodge": "sneak", "chaos": "chaos", "crew": "lift", "finale": "drop2"}.get(_s["act"])
    if _row and START[_row] != _s["from"]:
        print(f"  WARN act '{_s['act']}' starts at bar {_s['from']} in timeline.json but '{_row}' is at {START[_row]}")


def chord_at(t):
    bar = min(BARS - 1, int(t / BAR + 1e-6))
    beat = (t - T(bar)) / BEAT
    if bar == START["hit"]:
        return 0 if beat < 0.95 else (1 if beat < 1.95 else 3)
    if bar == START["voice"]:
        return [0, 1, 3, 3][min(3, int(beat + 0.05))]
    return CHORD[bar]


# The written silences (start, end): the music is silent inside; SFX cued inside still play.
SILENCES = [(T(START["hit"], 0.4), T(START["hit"], 1)), (T(START["exits"], 3.5), T(START["exits"] + 1))]

# ============================================================ drums: trailer 1's kit, layered
drums, room, bassb, chords, lead, fx, pads = Bus(), Bus(), Bus(), Bus(), Bus(), Bus(), Bus()
kicks = []
OWNED = {"bell": [], "impact": [], "tick": []}  # music plays these; matching act cues are not doubled


def layer(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[: len(s)] += s
    return out


def kick_l(big=False):
    """Trailer 1's kick with a sub layer under it and a click on top."""
    k = kick(big)
    n = len(k)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * np.cumsum(47 + 25 * np.exp(-t / 0.03)) / SR) * np.exp(-t / (0.34 if big else 0.2))
    click = hp(noise(n), 3000) * np.exp(-t / 0.0025) * 0.45 + np.sin(2 * np.pi * 3200 * t) * np.exp(-t / 0.004) * 0.2
    return np.tanh(k * 1.1 + sub * 0.5 * np.clip(t / 0.003, 0, 1) + click) * 0.92


def snare_l(level=1.0):
    """Trailer 1's snare and clap stacked, with a short body."""
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(185 + 40 * np.exp(-t / 0.01)) / SR) * np.exp(-t / 0.06) * 0.4
    return layer(snare(1.0), clap() * 0.6, body) * level


def tom(f):
    n = int(SR * 0.4)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.5 * np.exp(-t / 0.02))) / SR) * np.exp(-t / 0.2)
    x += 0.25 * bp(noise(n), 300, 4000) * np.exp(-t / 0.03)
    return np.tanh(x * 1.4) * 0.7


def cowbell():
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    s = pulse(587.0, n, 0.5) + pulse(845.0, n, 0.5)
    return bp(s, 500, 3200) * (np.exp(-t / 0.05) * 0.7 + np.exp(-t / 0.2) * 0.3) * 0.3


def shaker():
    n = int(SR * 0.07)
    t = np.arange(n) / SR
    return hp(noise(n), 6000, 4) * np.sin(np.pi * t / t[-1]) ** 2 * 0.4


def tamb():
    n = int(SR * 0.18)
    t = np.arange(n) / SR
    jingle = sum(np.sin(2 * np.pi * f * t + rng.random() * 6) for f in (5400, 6800, 7900, 9100, 10400)) / 5
    return (0.6 * jingle + 0.5 * hp(noise(n), 7000)) * np.exp(-t / 0.04) * 0.4


def K(t, big=False, g=1.0):
    drums.add(t, kick_l(big), g)
    kicks.append(t)


def SN(t, g=0.6, rm=0.35, pan=0.0):
    drums.add(t, snare_l(), g, pan=pan)
    room.add(t, snare_l(), g * rm, pan=pan)


def hats16(bar, g=0.34, beats=range(4), opens=(), vel=(1.0, 0.35, 0.62, 0.42), pan=0.25, eighths=False):
    for beat in beats:
        for s in range(4):
            if eighths and s % 2:
                continue
            bt = beat + s / 4
            if bt in opens:
                drums.add(T(bar, bt), hat(True), g * 0.9, pan=-pan)
            else:
                drums.add(T(bar, bt), hat(), g * vel[s], pan=pan)


def ghosts(bar, beats, g=0.12):
    for bt in beats:
        drums.add(T(bar, bt), snare(0.5), g, pan=-0.15)


def fill(bar, beat0=3.0, n=4, g=0.5):
    """Tom fill on 16ths into the next section, ending on a snare."""
    fs = [220, 180, 150, 120, 100, 90][:n]
    for k, f in enumerate(fs):
        t = T(bar, beat0 + k * 0.25)
        drums.add(t, tom(f), g * (0.8 + 0.08 * k), pan=0.4 - 0.25 * k)
        room.add(t, tom(f), g * 0.3)


def roll(bar, beat0=0, kinds=((0, 4, 0.5), (2, 4, 0.25), (3, 6, 0.125)), g0=0.25):
    """Snare roll: (start beat, hits, spacing) phases, crescendo."""
    i = 0
    for b0, n, sp in kinds:
        for k in range(n):
            SN(T(bar, beat0 + b0 + sp * k), g0 + 0.035 * i, rm=0.2)
            i += 1


def beat_four(bar, g=1.0, opens=(3.5,), ghost=True, hats=True, eighths=False, beats=4):
    for beat in range(beats):
        K(T(bar, beat), g=0.95 * g)
    for beat in (1, 3):
        if beat < beats:
            SN(T(bar, beat), 0.62 * g)
    if hats:
        hats16(bar, 0.34 * g, beats=range(beats), opens=opens, eighths=eighths)
    if ghost:
        ghosts(bar, [b_ for b_ in (1.75, 2.5, 3.25) if b_ < beats], 0.11 * g)


def beat_break(bar, g=1.0, opens=(1.5, 3.5)):
    """Breakbeat: kick 1, 2-and, 3-and; snare 2 and 4; ghosts in between."""
    for bt in (0, 1.5, 2.5):
        K(T(bar, bt), g=0.95 * g)
    K(T(bar, 3.75), g=0.5 * g)
    for bt in (1, 3):
        SN(T(bar, bt), 0.66 * g)
    ghosts(bar, (0.75, 1.75, 2.25, 3.5), 0.14 * g)
    hats16(bar, 0.36 * g, opens=opens)


def beat_half(bar, g=1.0, big=True):
    """Half time: kick on 1 (and 3-and), a huge snare on 3."""
    K(T(bar, 0), big=big, g=g)
    K(T(bar, 2.5), g=0.7 * g)
    SN(T(bar, 2), 0.8 * g, rm=0.7)
    drums.add(T(bar, 2), clap(), 0.4 * g)
    hats16(bar, 0.3 * g, opens=(1.5, 3.5), eighths=True)
    ghosts(bar, (1.25, 3.75), 0.12 * g)


def percussion(bar, g=1.0):
    for k in range(16):
        drums.add(T(bar, k / 4), shaker(), g * (0.22 if k % 2 else 0.12), pan=-0.5)
    for k in range(4):
        drums.add(T(bar, k + 0.5), tamb(), g * 0.34, pan=0.5)
    for bt in (0, 0.75, 1.5, 2.5, 3, 3.5):
        drums.add(T(bar, bt), cowbell(), g * (0.3 if bt in (0, 2.5) else 0.18), pan=0.3)


# ============================================================ tonal parts (trailer 1's)
def stab(ci, t, dur, gain=0.3, cutoff=5500, octave=12):
    l, rr = supersaw([n + octave for n in PROG[ci]] + [PROG[ci][0]], dur, cutoff=cutoff)
    e = env(len(l), 0.003, 0.12, 0.35, 0.05)
    chords.add(t, l * e, gain, pan=-0.7)
    chords.add(t, rr * e, gain, pan=0.7)


def hook_bar(bar, ci, gain=0.26, octave=0, echo=True, pan=-0.1):
    for step, ln, m in HOOK[ci]:
        t = T(bar, step / 4)
        lead.add(t, chip_lead(m + octave, S16 * ln * 0.92), gain, pan=pan)
        if echo:
            lead.add(t + BEAT * 0.75, chip_lead(m + octave, S16 * ln * 0.8), gain * 0.27, pan=0.5)  # echo


def arp_bar(bar, ci, gain=0.10, lift=False):
    notes = [n + 12 for n in PROG[ci]]
    for k in range(16):
        up = (12 if k >= 8 else 0) if lift else (12 if k % 6 > 2 else 0)
        lead.add(T(bar, k / 4), blip(notes[k % 3] + up, S16 * 0.9, 0.125), gain + (0.004 * k if lift else 0),
                 pan=0.45 * (1 if k % 2 else -1))


def band(bar, arp=False, lead_on=True, bass_on=True, stabs=True, stab_gain=0.3):
    """Trailer 1's groove minus the drums: root/octave bass, offbeat stabs, the hook, the arp."""
    ci = CHORD[bar]
    if bass_on:
        r = ROOTS[ci]
        for k in range(8):
            bassb.add(T(bar, k / 2), bass(r + (12 if k % 2 else 0), BEAT * 0.48), 0.55)
    if stabs:
        for beat in range(4):
            stab(ci, T(bar, beat + 0.5), BEAT * 0.42, stab_gain)
    if lead_on:
        hook_bar(bar, ci)
    if arp:
        arp_bar(bar, ci)


def pad_swell(bar, bars, notes, gain=0.16, c0=500, c1=3500):
    pl, pr = supersaw(notes, BAR * bars, cutoff=900, voices=4, spread=0.12)
    fade = np.clip(np.arange(len(pl)) / (SR * 1.5), 0, 1) * env(len(pl), 0.001, 1, 1, 0.4)
    pads.add(T(bar), sweep_lp(pl, c0, c1, curve=2.5) * fade, gain, pan=-0.6)
    pads.add(T(bar), sweep_lp(pr, c0, c1, curve=2.5) * fade, gain, pan=0.6)


def whoosh_into(t, length=0.55, gain=0.9):
    w, pk = whoosh(length)
    fx.add(t - pk, w, gain)


# fills and crashes at section changes: (fill on the bar before, crash on the downbeat)
CHANGE = {"drop1": (None, True), "sneak": ("toms", False), "hit": ("short", False), "voice": (None, True),
          "talk": ("short", True), "chaos": ("toms", True), "canteen": ("toms", True), "lift": (None, True),
          "maps": ("toms", True), "exits": ("toms", True), "drop2": (None, True), "escape": ("toms", True),
          "bell": ("toms", True), "logo": (None, True), "soon": ("toms", True)}


def build_music(accents):
    s = START
    # ---- intro: the bell, the clock, a sneaky bass, the pad opening ----------------------------------
    b0 = s["intro"]
    fx.add(T(b0), bell_ring(1.7), 0.9)
    OWNED["bell"].append(T(b0))
    for b in range(16):  # the clock ticks through intro and build
        fx.add(T(b0, b), tick(b % 2 == 0), 0.55 if b < 8 else 0.4, pan=0.3 if b % 2 else -0.3)
        OWNED["tick"].append(T(b0, b))
    for bar in range(b0, b0 + 4):
        for k, m in enumerate(SNEAK[bar % 2]):
            if m is not None:
                bassb.add(T(bar, k / 2), pizz(m + 12, BEAT * 0.45), 0.55)
    pad_swell(b0, 4, [50, 57, 62, 65])
    for k, m in enumerate(TEASER):  # four chip notes answering the bell
        lead.add(T(b0 + 1, k), chip_lead(m, BEAT * 0.4, vib=False), 0.18, pan=0.2)

    # ---- build: drums in, riser, alarm blips, roll, RUN! -------------------------------------------------
    b0 = s["build"]
    K(T(b0, 0), g=0.7)
    K(T(b0, 2), g=0.7)
    SN(T(b0, 1), 0.3)
    SN(T(b0, 3), 0.34)
    hats16(b0, 0.2, eighths=True)
    for beat in range(4):
        K(T(b0 + 1, beat), g=0.75)
    hats16(b0 + 1, 0.22)
    roll(b0 + 1, g0=0.16)
    fx.add(T(b0), riser(BAR * 2 - BEAT * 0.25), 0.55)
    for k in range(4):  # suspicion alarm blips climbing
        fx.add(T(b0 + 1, k), blip(79 + k * 3, 0.12, 0.25), 0.22)
    stab(3, T(b0 + 1, 3), BEAT * 0.9, 0.34)  # RUN!

    # ---- DROP 1 ---------------------------------------------------------------------------------------
    b0 = s["drop1"]
    drums.add(T(b0), impact(), 0.8)
    OWNED["impact"].append(T(b0))
    K(T(b0), big=True)
    for bar in (b0, b0 + 1):
        beat_four(bar, g=1.1, opens=(0.5, 1.5, 2.5, 3.5))
        band(bar, arp=True)
    whoosh_into(T(b0 + 2), 0.5, 0.6)

    # ---- sneak ------------------------------------------------------------------------------------------
    b0 = s["sneak"]
    for bar in (b0, b0 + 1):
        K(T(bar, 0), g=0.85)
        K(T(bar, 2.5), g=0.55)
        SN(T(bar, 1), 0.3, rm=0.5)
        SN(T(bar, 3), 0.34, rm=0.5)
        ghosts(bar, (0.75, 2.25, 3.75), 0.1)
        hats16(bar, 0.2, vel=(1.0, 0.25, 0.55, 0.3))
        for k, m in enumerate(SNEAK[bar % 2]):
            if m is not None:
                bassb.add(T(bar, k / 2), pizz(m + 12, BEAT * 0.45), 0.6)
                bassb.add(T(bar, k / 2), bass(m, BEAT * 0.4), 0.3)
    pad_swell(b0, 2, [50, 57, 62, 65], gain=0.12, c0=600, c1=1600)
    for k, m in enumerate(TEASER):
        lead.add(T(b0 + 1, k), pizz(m, BEAT * 0.4), 0.3, pan=0.2)
        lead.add(T(b0 + 1, k + 0.75), pizz(m, BEAT * 0.3), 0.08, pan=-0.5)

    # ---- hit: 8.0 hit, silence, "Who's talking?!" stab, 16th stabs ----------------------------------
    b0 = s["hit"]
    K(T(b0), big=True)
    drums.add(T(b0), crash(0.6), 0.6)
    SN(T(b0), 0.5)
    stab(0, T(b0), BEAT * 0.38, 0.4)
    bassb.add(T(b0), bass(38, BEAT * 0.38), 0.6)
    K(T(b0, 1), g=0.95)
    SN(T(b0, 1), 0.7, rm=0.6)
    stab(1, T(b0, 1), BEAT * 0.8, 0.42, octave=0)
    bassb.add(T(b0, 1), bass(34, BEAT * 0.8), 0.6)
    for k in range(8):
        stab(3, T(b0, 2 + k / 4), S16 * 0.8, 0.16 + 0.03 * k, cutoff=2500 + 600 * k)
        SN(T(b0, 2 + k / 4), 0.18 + 0.045 * k, rm=0.2)
        if k % 2 == 0:
            bassb.add(T(b0, 2 + k / 4), bass(36 + (12 if k % 4 else 0), BEAT * 0.4), 0.5)
            K(T(b0, 2 + k / 4), g=0.6 + 0.05 * k)

    # ---- voice: three claims on .0 .1 .2 (a hit each), the last one held to the next bar ------------------
    b0 = s["voice"]
    for beat, held in ((0, 1), (1, 1), (2, 2)):
        ci = chord_at(T(b0, beat) + 0.01)
        K(T(b0, beat), g=0.8)
        SN(T(b0, beat), 0.4, rm=0.6)
        l, rr = supersaw([n + 12 for n in PROG[ci]] + [PROG[ci][0]], BEAT * (held - 0.05), cutoff=4200)
        e = env(len(l), 0.004, 0.25, 0.55, 0.08)
        chords.add(T(b0, beat), l * e, 0.28, pan=-0.7)
        chords.add(T(b0, beat), rr * e, 0.28, pan=0.7)
        lead.add(T(b0, beat), chip_lead(TEASER[beat + 1], BEAT * (0.6 if held == 1 else 1.6), vib=held > 1), 0.12, pan=0.2)
    for k in range(8):  # still driving underneath: 8th bass, a light kick on 3 and 4
        ci = chord_at(T(b0, k / 2) + 0.01)
        bassb.add(T(b0, k / 2), bass(ROOTS[ci] + (12 if k % 2 else 0), BEAT * 0.45), 0.45)
    K(T(b0, 3), g=0.6)
    hats16(b0, 0.2, eighths=True)
    ghosts(b0, (0.75, 1.75, 2.75, 3.5), 0.09)

    # ---- talk: groove + blip arp, the excuse rows read -------------------------------------------------
    b0 = s["talk"]
    for bar in (b0, b0 + 1):
        beat_four(bar, g=0.85, opens=(1.5, 3.5), beats=4 if bar == b0 else 3)
        band(bar, arp=True, lead_on=False, stabs=True, stab_gain=0.2)
    whoosh_into(T(b0 + 2), 0.55, 0.8)

    # ---- chaos: CAUSE CHAOS (4/4, open hats), SURPRISE TEST (breakbeat, bouncy pizz) -----------------
    b0 = s["chaos"]
    for i, bar in enumerate(range(b0, b0 + 4)):
        if i < 2:
            beat_four(bar, opens=(0.5, 1.5, 2.5, 3.5))
        else:
            beat_break(bar)
            ci = CHORD[bar]
            for k in range(8):
                bassb.add(T(bar, k / 2 + 0.25), pizz(PROG[ci][k % 3] + 12, BEAT * 0.2), 0.22)
        band(bar)
    whoosh_into(T(b0 + 4), 0.5, 0.7)

    # ---- canteen: trailer 1's items bar, half time, a chime per beat ---------------------------------
    b0 = s["canteen"]
    for bar in (b0, b0 + 1):
        ci = CHORD[bar]
        beat_half(bar, g=0.9, big=False)
        l, rr = supersaw([n + 12 for n in PROG[ci]] + [PROG[ci][0] - 12], BAR, cutoff=6000)
        e = env(len(l), 0.01, 0.6, 0.6, 0.1)
        chords.add(T(bar), l * e, 0.34, pan=-0.7)
        chords.add(T(bar), rr * e, 0.34, pan=0.7)
        r = ROOTS[ci]
        for k in range(4):
            bassb.add(T(bar, k), bass(r + (12 if k % 2 else 0), BEAT * 0.9), 0.55)
        arp_bar(bar, ci, 0.12, lift=True)
        for beat in range(4):  # an item lands on every beat
            fx.add(T(bar, beat), ching(), 0.5)
    fx.add(T(b0), riser(BAR * 2 - BEAT * 0.5), 0.4)
    roll(b0 + 1, 2, ((0, 4, 0.25), (1, 3, 0.125)), 0.3)
    whoosh_into(T(b0 + 2), 0.7, 0.9)

    # ---- lift: friends; shaker, tambourine, cowbell, claps on every beat -------------------------------
    b0 = s["lift"]
    for bar in (b0, b0 + 1):
        beat_four(bar, opens=(3.5,))
        for beat in range(4):
            drums.add(T(bar, beat), clap(), 0.4, pan=0.3 * (1 if beat % 2 else -1))
        for k in range(8):
            drums.add(T(bar, k / 2 + 0.25), clap(), 0.1, pan=0.6 * (1 if k % 2 else -1))  # the gang
        percussion(bar)
        band(bar, arp=True)
        hook_bar(bar, CHORD[bar], 0.1, octave=12, echo=False, pan=0.3)

    # ---- maps build ------------------------------------------------------------------------------------
    b0 = s["maps"]
    for bar in (b0, b0 + 1):
        beat_four(bar, g=0.9 if bar == b0 else 1.0, eighths=bar == b0, opens=(1.5, 3.5) if bar > b0 else (3.5,))
        band(bar, arp=True, lead_on=False)
        if bar > b0:
            whoosh_into(T(bar), 0.45, 0.7)
        for k in range(4):
            lead.add(T(bar, k), chip_lead(TEASER[k] + (5 if bar > b0 else 0), BEAT * 0.4, vib=False), 0.12, pan=0.2)
    whoosh_into(T(b0), 0.5, 0.8)
    fx.add(T(b0 + 1), riser(BAR * 2 - BEAT * 0.5), 0.5)

    # ---- exits: 8ths, roll, crash zoom on .3, then silence ------------------------------------------------
    b0 = s["exits"]
    ci = CHORD[b0]
    for k in range(6):
        K(T(b0, k / 2), g=0.75 + 0.03 * k)
        fx.add(T(b0, k / 2), blip(91 + k, 0.08, 0.5), 0.13, pan=0.2)  # an exit per 8th
        bassb.add(T(b0, k / 2), bass(ROOTS[ci] + (12 if k % 2 else 0), BEAT * 0.45), 0.5 + 0.02 * k)
        stab(ci, T(b0, k / 2), BEAT * 0.4, 0.14 + 0.03 * k, cutoff=2000 + 800 * k)
    hats16(b0, 0.3, beats=range(3))
    roll(b0, 0, ((0, 4, 0.5), (2, 4, 0.25)), 0.3)
    K(T(b0, 3), big=True)  # crash zoom
    SN(T(b0, 3), 0.7, rm=0.3)
    stab(ci, T(b0, 3), BEAT * 0.45, 0.45)

    # ---- DROP 2: breakbeat chase, then the half-time apex ----------------------------------------------
    b0 = s["drop2"]
    drums.add(T(b0), impact(), 0.9)
    OWNED["impact"].append(T(b0))
    K(T(b0), big=True)
    beat_break(b0, g=1.05)
    K(T(b0, 1), g=0.6)
    K(T(b0, 3), g=0.6)
    drums.add(T(b0 + 1), impact(), 0.8)  # slow-mo apex
    OWNED["impact"].append(T(b0 + 1))
    drums.add(T(b0 + 1), crash(2.6), 0.6)
    beat_half(b0 + 1, g=1.1)
    fill(b0 + 1, 3.5, 2, 0.45)
    for bar in (b0, b0 + 1):
        band(bar, arp=True)
        hook_bar(bar, CHORD[bar], 0.1, octave=12, echo=False, pan=0.35)
        stab(CHORD[bar], T(bar), BEAT * 0.9, 0.3, octave=0)

    # ---- escape: the win arpeggio -------------------------------------------------------------------
    b0 = s["escape"]
    beat_four(b0, opens=(0.5, 1.5, 2.5))
    band(b0, lead_on=False)
    hook_bar(b0, CHORD[b0], 0.2)
    for k, m in enumerate([77, 81, 84, 89, 84, 89]):  # sfx.gd win (72 76 79 84 79 84), in F
        lead.add(T(b0, 2 + k / 4), chip_lead(m, S16 * (0.9 if k < 5 else 3.5), vib=k == 5), 0.24, pan=-0.1)
    for m in [77, 81, 84, 93]:
        lead.add(T(b0, 3.5), chip_lead(m, BEAT * 0.9), 0.07, pan=0.3)

    # ---- FINAL BELL held, NEW RANK on +1.2 ---------------------------------------------------------------
    b0 = s["bell"]
    K(T(b0), big=True)
    fx.add(T(b0), bell_ring(2.4), 0.8)
    OWNED["bell"].append(T(b0))
    l, rr = supersaw([n + 12 for n in C] + [C[0] - 12], BAR * 1.5 + 0.2, cutoff=4200, voices=7)
    e = env(len(l), 0.01, 1.2, 0.55, 0.25)
    chords.add(T(b0), l * e, 0.36, pan=-0.7)
    chords.add(T(b0), rr * e, 0.36, pan=0.7)
    bassb.add(T(b0), bass(36, BAR * 1.5) * env(int(SR * BAR * 1.5), 0.003, 1.0, 0.4, 0.3), 0.55)
    for b in range(6):  # the clock again
        fx.add(T(b0, b), tick(b % 2 == 0), 0.45, pan=0.3 if b % 2 else -0.3)
        OWNED["tick"].append(T(b0, b))
    fx.add(T(b0, 2), riser(T(b0 + 2) - T(b0, 2) - BEAT * 0.1), 0.35)
    K(T(b0 + 1, 2))
    drums.add(T(b0 + 1, 2), crash(1.0), 0.45)
    for k, (beat, frac) in enumerate([(2, 0), (2, 0.5), (3, 0), (3, 0.25), (3, 0.5)]):  # rank-up steps
        lead.add(T(b0 + 1, beat + frac), chip_lead(79 + [0, 5, 9, 12, 17][k], BEAT * 0.4, vib=False), 0.22)
    for k in range(4):
        bassb.add(T(b0 + 1, 2 + k / 2), bass(36 + (12 if k % 2 else 0), BEAT * 0.45), 0.5)
        K(T(b0 + 1, 2 + k / 2), g=0.6 + 0.08 * k)
    roll(b0 + 1, 2, ((0, 4, 0.25), (1, 4, 0.125)), 0.35)
    whoosh_into(T(b0 + 2), 0.7, 1.0)

    # ---- logo slam, tagline groove ----------------------------------------------------------------------
    b0 = s["logo"]
    drums.add(T(b0), impact(), 1.0)
    OWNED["impact"].append(T(b0))
    K(T(b0), big=True)
    beat_four(b0, opens=(1.5, 3.5))
    beat_four(b0 + 1, opens=(0.5, 1.5, 2.5))
    band(b0)
    band(b0 + 1, arp=True)

    # ---- COMING SOON: the last chord, the bell ---------------------------------------------------------
    b0 = s["soon"]
    K(T(b0), big=True)
    SN(T(b0), 0.6, rm=1.0)
    l, rr = supersaw([50, 57, 62, 65, 69, 74], BAR * 1.2, cutoff=4500, voices=7)
    e = env(len(l), 0.004, 0.7, 0.35, 0.8)
    chords.add(T(b0), l * e, 0.42, pan=-0.7)
    chords.add(T(b0), rr * e, 0.42, pan=0.7)
    bassb.add(T(b0), bass(38, BAR * 1.1) * env(int(SR * BAR * 1.1), 0.003, 0.8, 0.3, 0.6), 0.6)
    lead.add(T(b0), chip_lead(86, BEAT * 1.5), 0.24)
    fx.add(T(b0, 1), bell_ring(1.4), 0.45)
    OWNED["bell"].append(T(b0, 1))

    # ---- section changes: tom fills into them, crashes on their downbeats --------------------------------
    for name, (kind, cr) in CHANGE.items():
        b_ = START[name]
        if cr:
            drums.add(T(b_), crash(2.4), 0.7)
        if kind == "toms":
            fill(b_ - 1, 3.0, 4)
        elif kind == "short":
            fill(b_ - 1, 3.5, 2, 0.4)

    # ---- accents on the act's big hits --------------------------------------------------------------
    last = -1.0
    for t, name in sorted(accents):
        if t - last < BEAT * 0.45 or any(a - 0.01 <= t < b_ for a, b_ in SILENCES) or t >= T(START["soon"]):
            continue
        if any(abs(t - o) < 0.05 for o in OWNED["impact"]):
            continue
        last = t
        ci = chord_at(t + 0.01)
        if name in ("stamp", "impact", "slap"):
            stab(ci, t, BEAT * 0.35, 0.22 if name != "slap" else 0.16, octave=0)
            if name == "impact":
                drums.add(t, crash(1.2), 0.22)
        elif name == "crash":
            drums.add(t, crash(1.4), 0.25)
            stab(ci, t, BEAT * 0.3, 0.16, octave=0)
        elif name == "star":
            lead.add(t, blip(PROG[ci][0] + 24, 0.14, 0.5), 0.14, pan=0.3)


# ============================================================ SFX (steam_music.py engine, local bars + offsets)
def load_cues():
    cues = []
    offsets = TL.get("offsets", {})
    for f in sorted((ROOT / "src/steam/sfx").glob("*.json")):
        try:
            data = json.loads(f.read_text() or "[]")
        except (json.JSONDecodeError, OSError) as e:
            print(f"  WARN {f.name}: unreadable ({e}), skipped")
            continue
        if not isinstance(data, list):
            print(f"  WARN {f.name}: not a list, skipped")
            continue
        if f.stem not in offsets:
            print(f"  WARN {f.name}: no offset for act '{f.stem}' in timeline.json, using 0")
        off = offsets.get(f.stem, 0)
        for c in data:
            try:
                name, bar, beat = c[0], float(c[1]), float(c[2])
                gain = float(c[3]) if len(c) > 3 else 1.0
            except (TypeError, ValueError, IndexError, KeyError):
                print(f"  WARN {f.name}: bad cue {c!r}, skipped")
                continue
            if name not in S.SFX:
                print(f"  WARN {f.name}: unknown sound '{name}' at {bar:g}.{beat:g}, skipped")
                continue
            t = T(bar + off, beat)
            if not 0 <= t < LENGTH:
                print(f"  WARN {f.name}: '{name}' at local {bar:g}.{beat:g} is outside the film, skipped")
                continue
            cues.append((f.stem, name, bar + off, beat, gain, t))
    return cues


def build_sfx(cues):
    small, big = np.zeros((S.N, 2)), np.zeros((S.N, 2))
    log = []
    for src, name, bar, beat, gain, at in cues:
        if any(abs(at - o) < 0.04 for o in OWNED.get(name, [])):
            print(f"  note {src}: '{name}' at {bar:g}.{beat:g} is already in the score, not doubled")
            continue
        S.R = np.random.default_rng(zlib.crc32(f"{name}:{bar}:{beat}".encode()))
        x = S.SFX[name]()
        x = x / (np.abs(x).max() + 1e-9) * 10 ** (S.LEVEL[name] / 20)
        lead_in = S.LEAD_IN.get(name)
        lead_in = S.onset(x) / SR if lead_in is None else lead_in
        x = S.stereo(x, {"psst": -0.3, "laugh": 0.2}.get(name, 0.0))
        t0 = at - lead_in
        for a, _ in SILENCES:  # a sound running into a silence stops at its edge
            if t0 < a - 0.01 and t0 + len(x) / SR > a - 0.005:
                k = max(1, int((a - t0) * SR))
                f = min(k, int(0.005 * SR))
                x = x[:k].copy()
                x[-f:] *= np.linspace(1, 0, f)[:, None]
        S.place(big if name in S.BIG else small, t0, x, gain)
        log.append((src, name, bar, beat, at))
    print(f"  {len(log)} SFX placed")
    return S.hp(small, 90), S.hp(big, 38), log


# ============================================================ mix + master
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


def mute_mask():
    m = np.ones(N)
    for a, b_ in SILENCES:
        ia, ib = int(round(a * SR)), int(round(b_ * SR))
        k = int(0.012 * SR)
        m[ia - k:ia] = np.linspace(1, 0, k)
        m[ia:ib] = 0
        k = int(0.002 * SR)
        m[ib:ib + k] = np.linspace(0, 1, k)
    return m


def glue(st, thr_db=-26.0, ratio=8.0, rel=0.06):
    """Hard-working compressor for the parallel drum bus (linked stereo, ~1 ms attack)."""
    B = 32
    p = (st ** 2).mean(0)
    nb = (len(p) + B - 1) // B
    lv = 10 * np.log10(np.pad(p, (0, nb * B - len(p))).reshape(nb, B).mean(1) + 1e-12)
    want = np.minimum(0.0, (thr_db - lv) * (1 - 1 / ratio))
    a = np.exp(-B / (rel * SR))
    g = np.empty(nb)
    e = 0.0
    for i in range(nb):
        e = want[i] if want[i] < e else e * a + want[i] * (1 - a)
        g[i] = e
    gs = 10 ** (np.repeat(g, B)[: st.shape[1]] / 20)
    return st * gs


def mix_music():
    M = len(drums.l)
    sc = sidechain(M)
    dr = drums.stereo() + reverb(room.stereo(), 0.7, 0.5)  # the kit and its room
    crushed = glue(dr)
    crushed *= np.sqrt((dr ** 2).mean() / ((crushed ** 2).mean() + 1e-12))
    dr = dr + 0.55 * np.tanh(crushed * 1.5) / 1.5  # parallel compression
    bs = bassb.stereo() * sc
    ch = chords.stereo() * sc
    pd = pads.stereo()
    ld = lead.stereo()
    fxx = fx.stereo()
    wet = reverb(ch * 0.8 + ld * 0.9 + pd + fxx * 0.3, 2.2, 0.26)
    wet = np.stack([lp(wet[0], 5000), lp(wet[1], 5000)])
    mix = dr * DRUMS + bs * 0.9 + ch * 1.1 + pd + ld * 1.3 + fxx + wet
    mix = np.stack([hp(mix[0], 28), hp(mix[1], 28)])[:, :N]
    # trailer 1's glue: a gentle tanh over the whole cue
    peak = np.max(np.abs(mix))
    mix = np.tanh(mix / peak * 1.35) / np.tanh(1.35)
    return S.prep(mix.T) * mute_mask()[:, None]


DRUMS = 0.62


def checks(x):
    seg = lambda a, b_: S.seg(x, T(*a), T(*b_))  # noqa: E731
    sec = lambda name, n=None: seg((START[name], 0), (START[name] + (n or len(dict(SECTIONS)[name])), 0))  # noqa: E731
    peak = lambda a, b_: 20 * np.log10(np.abs(x[int(T(*a) * SR):int(T(*b_) * SR)]).max() + 1e-12)  # noqa: E731
    h, e_ = START["hit"], START["exits"]
    loud2 = max(seg((b_, 0), (b_ + 2, 0)) for b_ in range(0, BARS - 1)
                if not START["exits"] <= b_ + 1 and b_ <= START["drop2"] + 1 or b_ < START["exits"] - 1)
    tests = [
        ("cold open 5 dB under drop 1", sec("intro") < sec("drop1") - 5),
        ("hush after the bell 10 dB under drop 1", seg((1, 0), (2, 0)) < sec("drop1") - 10),
        ("drop 1 louder than the build", sec("drop1") > sec("build") + 1.5),
        ("sneak quieter than drop 1 and chaos", sec("sneak") < min(sec("drop1"), sec("chaos", 2)) - 2),
        ("voice bar lighter than chaos", sec("voice") < sec("chaos", 2) - 0.5),
        ("drop 2 is the loudest 2-bar stretch", sec("drop2") >= loud2 - 0.3),
        ("FINAL BELL hold drops back", seg((START["bell"], 1), (START["bell"] + 1, 2)) < sec("drop2") - 3),
        (f"{h}.0.4-{h}.1 silent (peak < -80 dBFS)", peak((h, 0.4), (h, 1)) < -80),
        (f"{e_}.3.5-{e_ + 1}.0 silent (peak < -80 dBFS)", peak((e_, 3.5), (e_ + 1, 0)) < -80),
        ("logo louder than the ring-out", sec("logo", 1) > sec("soon") + 3),
    ]
    print()
    for name, ok in tests:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")


def main():
    print("reading act cues...")
    cues = load_cues()
    accents = [(t, name) for _, name, _, _, _, t in cues if name in ("stamp", "impact", "slap", "crash", "star")]
    print(f"  {len(cues)} cues, {len(accents)} big ones become musical accents")
    print("building score...")
    build_music(accents)
    music = mix_music()
    music *= 10 ** ((S.TARGET_LUFS - S.lufs(music)) / 20)
    print("placing SFX...")
    small, big, log = build_sfx(cues)
    mdb = S.short_db(music)
    mute = np.ones((S.N, 1))
    mute[:N, 0] = mute_mask()  # no reverb tails inside the silences; SFX cued there play dry
    small, g_small = S.keyed(S.prep(small + S.reverb(small * 0.3) * mute), mdb, -10.0, -26.0)
    big, g_big = S.keyed(S.prep(big + S.reverb(big * 0.3) * mute), mdb, -4.0, -20.0)
    sfx = small + big
    out = ROOT / "public/audio/steam"
    m, _, gs_m = S.master(music)
    mix, g, gs_x = S.master(music + sfx)
    s = sfx * g
    tp = S.true_peak(s)
    if tp > S.CEILING_DBTP:
        s *= 10 ** ((S.CEILING_DBTP - tp) / 20)
    S.write(out / "music.wav", m)
    S.write(out / "sfx.wav", s)
    S.write(out / "mix.wav", mix)
    S.report("music.wav", m, gs_m)
    checks(m)
    S.report("mix.wav", mix, gs_x)
    print(f"\nsfx.wav: true peak {S.true_peak(s):.2f} dBTP, {S.lufs(s):.1f} LUFS; SFX turned down up to "
          f"{-20 * np.log10(g_small.min()):.1f} dB (small) / {-20 * np.log10(g_big.min()):.1f} dB (big) to stay under the music")
    d = [S.seg(sfx, at, at + 0.3) - S.seg(music, at, at + 0.3) for *_, at in log
         if not any(a - 0.01 <= at < b_ for a, b_ in SILENCES)]
    if d:
        print(f"SFX minus music over 300 ms from each hit: median {np.median(d):+.1f} dB, 90th pct {np.percentile(d, 90):+.1f} dB")


if __name__ == "__main__":
    main()
