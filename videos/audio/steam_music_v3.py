"""Bunk Master Steam trailer, score v3: trailer 1's cue (audio/make_music.py) grown into the 56.25 s film.

Same sound as trailer 1: 128 BPM D-minor chip-pop, i VI III VII (Dm Bb F C), supersaw offbeat stabs, chip lead
with vibrato and a dotted-8th echo, pizz sneak bass, root/octave saw bass with sub, blip arps, the electric school
bell and the clock, big drops. The instruments and the hook are copied verbatim from make_music.py; only the
arrangement is new, following the global-bar music map in src/steam/timeline.json (30 bars):

  0-1  bell on 0.0, clock ticks, pizz sneak bass, Dm pad opening; chip teaser answers the bell (bar 1)
  2-3  drums in, riser, alarm blips climbing, snare roll 8ths -> 16ths -> 32nds into RUN! (3.3)
  4-5  DROP 1: impact + crash, full groove, the hook (Dm, Bb)
  6-7  sneaky: pizz sneak line, kick on 1 and 3, soft hats, teaser on pizz
  8    8.0 hit, silence to 8.1, "Who's talking?!" stab on 8.1, supersaw stabs on 16ths from 8.2
  9-10 TALK YOUR WAY OUT: groove + blip arp (no lead, the excuse rows read); drums drop on 10.3.5
  11-14 CAUSE CHAOS / SURPRISE TEST: full hook over Dm Bb F C, open hats; 13-14 bouncy pizz offbeats
  15-16 canteen: trailer 1's half-time items bar (Bb, C), a chime on every beat, rising blip arps, riser
  17-18 lift (F, C, major side of the key): four-on-the-floor, claps on every beat, hook bars 3-4
  19-20 maps build: groove + arp, crash and whoosh on every bar
  21   exits on every beat, snare roll, crash-zoom hit 21.3, silence 21.3.5 -> 22.0
  22-23 DROP 2 (biggest): hook doubled an octave up + arp + open hats; apex slam on 23.0
  24   escape: the game's win arpeggio on 24.2
  25-26 FINAL BELL: the bell, the clock again over a held C chord; 26.2 NEW RANK chip steps + roll
  27-28 logo slam 27.0, groove with the hook under the tagline
  29   COMING SOON: the final chord, the bell, fade over the last 1.2 s

Accents follow the act SFX: every big cue (stamp, impact, slap, crash, star) also gets a musical hit on the
current chord, so re-timed act hits keep landing with the score. SFX cues are read from src/steam/sfx/<act>.json
in LOCAL bars and shifted by timeline.json `offsets`; the SFX engine (recipes, placement on the transient,
music-keyed levels) is audio/steam_music.py's.

Run from videos/:  uv run --with numpy --with scipy python audio/steam_music_v3.py
Writes public/audio/steam/{music,sfx,mix}.wav: 44.1 kHz stereo, exactly 56.25 s, -14 LUFS, true peak -1.5 dBTP.
"""
import json
import sys
import zlib
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_music as S  # noqa: E402  (SFX recipes, loudness, limiter, writer)

ROOT = Path(__file__).resolve().parent.parent
TL = json.loads((ROOT / "src/steam/timeline.json").read_text())
SR = 44100
BPM = float(TL["bpm"])
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = TL["bars"]
LENGTH = BARS * BAR  # 56.25 s
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

# chord (index into PROG) per global bar; bar 8 moves Dm -> Bb (8.1) -> C (8.2)
CHORD = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1, 3, 2, 3, 0, 1, 3, 0, 1, 2, 3, 3, 0, 1, 0]
assert len(CHORD) == BARS


def chord_at(t):
    bar = min(BARS - 1, int(t / BAR + 1e-6))
    if bar == 8:
        beat = (t - T(8)) / BEAT
        return 0 if beat < 0.95 else (1 if beat < 1.95 else 3)
    return CHORD[bar]


# The written silences (start, end): the music is silent inside; SFX cued inside still play.
SILENCES = [(T(8, 0.4), T(8, 1)), (T(21, 3.5), T(22))]

# ============================================================ arrangement
drums, bassb, chords, lead, fx, pads = Bus(), Bus(), Bus(), Bus(), Bus(), Bus()
kicks = []
OWNED = {"bell": [], "impact": [], "tick": []}  # music plays these; matching act cues are not doubled


def K(t, big=False, g=1.0):
    drums.add(t, kick(big), g)
    kicks.append(t)


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


def groove(bar, full=True, arp=False, lead_on=True, open_hats=False, bass_on=True, stabs=True, beats=4):
    ci = CHORD[bar]
    for beat in range(beats):
        K(T(bar, beat))
    for beat in (1, 3):
        if beat < beats:
            drums.add(T(bar, beat), clap(), 0.62)
    for k in range(beats * 2):
        drums.add(T(bar, k / 2), hat(open_hats and k % 2 == 1), 0.42 if k % 2 else 0.18, pan=0.25)
    if full:
        for k in range(beats * 4):
            if k % 4 == 2:
                continue
            drums.add(T(bar, k / 4), hat(), 0.12, pan=-0.35)
    if bass_on:  # root / octave eighths
        r = ROOTS[ci]
        for k in range(8):
            bassb.add(T(bar, k / 2), bass(r + (12 if k % 2 else 0), BEAT * 0.48), 0.55)
    if stabs:  # offbeat supersaw stabs
        for beat in range(4):
            stab(ci, T(bar, beat + 0.5), BEAT * 0.42)
    if lead_on:
        hook_bar(bar, ci)
    if arp:
        arp_bar(bar, ci)


def roll(bar, beat0=0, kinds=((0, 4, 0.5), (2, 4, 0.25), (3, 6, 0.125)), g0=0.25):
    """Snare roll: (start beat, hits, spacing) phases, crescendo."""
    i = 0
    for b0, n, sp in kinds:
        for k in range(n):
            drums.add(T(bar, beat0 + b0 + sp * k), snare(), g0 + 0.035 * i)
            i += 1


def pad_swell(bar, bars, notes, gain=0.16, c0=500, c1=3500):
    pl, pr = supersaw(notes, BAR * bars, cutoff=900, voices=4, spread=0.12)
    fade = np.clip(np.arange(len(pl)) / (SR * 1.5), 0, 1) * env(len(pl), 0.001, 1, 1, 0.4)
    pads.add(T(bar), sweep_lp(pl, c0, c1, curve=2.5) * fade, gain, pan=-0.6)
    pads.add(T(bar), sweep_lp(pr, c0, c1, curve=2.5) * fade, gain, pan=0.6)


def whoosh_into(t, length=0.55, gain=0.9):
    w, pk = whoosh(length)
    fx.add(t - pk, w, gain)


def build_music(accents):
    # ---- 0-1: the bell, the clock, a sneaky bass, the pad opening -------------------------------
    fx.add(T(0), bell_ring(1.7), 0.9)
    OWNED["bell"].append(T(0))
    for b in range(16):  # the clock ticks through the intro (bars 0-3)
        fx.add(T(0, b), tick(b % 2 == 0), 0.55 if b < 8 else 0.4, pan=0.3 if b % 2 else -0.3)
        OWNED["tick"].append(T(0, b))
    for bar in range(0, 4):
        for k, m in enumerate(SNEAK[bar % 2]):
            if m is not None:
                bassb.add(T(bar, k / 2), pizz(m + 12, BEAT * 0.45), 0.55)
    pad_swell(0, 4, [50, 57, 62, 65])
    for k, m in enumerate(TEASER):  # four chip notes answering the bell
        lead.add(T(1, k), chip_lead(m, BEAT * 0.4, vib=False), 0.18, pan=0.2)

    # ---- 2-3: drums in, build, riser, RUN! on 3.3 ------------------------------------------------
    for beat in (0, 2):
        K(T(2, beat))
    for beat in range(4):
        K(T(3, beat), g=0.9)
    for bar in (2, 3):
        for k in range(8):
            drums.add(T(bar, k / 2), hat(), 0.5 if k % 2 else 0.25, pan=0.25)
        drums.add(T(bar, 1), clap(), 0.55)
        drums.add(T(bar, 3), clap(), 0.55)
    roll(3)
    fx.add(T(2), riser(BAR * 2 - BEAT * 0.25), 0.55)
    for k in range(4):  # suspicion alarm blips climbing on each beat of bar 3
        fx.add(T(3, k), blip(79 + k * 3, 0.12, 0.25), 0.22)
    stab(3, T(3, 3), BEAT * 0.9, 0.34)  # RUN!

    # ---- 4-5: DROP 1 -------------------------------------------------------------------------------
    drums.add(T(4), impact(), 0.8)
    OWNED["impact"].append(T(4))
    drums.add(T(4), crash(), 0.8)
    groove(4)
    groove(5)
    whoosh_into(T(6), 0.5, 0.6)

    # ---- 6-7: sneaky ---------------------------------------------------------------------------------
    for bar in (6, 7):
        K(T(bar, 0), g=0.85)
        K(T(bar, 2), g=0.7)
        for beat in (1, 3):
            drums.add(T(bar, beat), clap(), 0.3)
        for k in range(8):
            drums.add(T(bar, k / 2), hat(), 0.32 if k % 2 else 0.14, pan=0.25)
        for k, m in enumerate(SNEAK[bar % 2]):
            if m is not None:
                bassb.add(T(bar, k / 2), pizz(m + 12, BEAT * 0.45), 0.6)
                bassb.add(T(bar, k / 2), bass(m, BEAT * 0.4), 0.3)
    pad_swell(6, 2, [50, 57, 62, 65], gain=0.12, c0=600, c1=1600)
    for k, m in enumerate(TEASER):
        lead.add(T(7, k), pizz(m, BEAT * 0.4), 0.3, pan=0.2)
        lead.add(T(7, k + 0.75), pizz(m, BEAT * 0.3), 0.08, pan=-0.5)

    # ---- 8: hit, silence, "Who's talking?!" stab, 16th stabs -------------------------------------
    K(T(8), big=True)
    drums.add(T(8), crash(0.6), 0.6)
    stab(0, T(8), BEAT * 0.38, 0.4)
    bassb.add(T(8), bass(38, BEAT * 0.38), 0.6)
    K(T(8, 1), g=0.9)
    drums.add(T(8, 1), clap(), 0.7)
    stab(1, T(8, 1), BEAT * 0.8, 0.42, octave=0)
    bassb.add(T(8, 1), bass(34, BEAT * 0.8), 0.6)
    for k in range(8):
        stab(3, T(8, 2 + k / 4), S16 * 0.8, 0.16 + 0.03 * k, cutoff=2500 + 600 * k)
        drums.add(T(8, 2 + k / 4), snare(), 0.2 + 0.04 * k)
        if k % 2 == 0:
            bassb.add(T(8, 2 + k / 4), bass(36 + (12 if k % 4 else 0), BEAT * 0.4), 0.5)

    # ---- 9-10: TALK YOUR WAY OUT ------------------------------------------------------------------
    for bar in (9, 10):  # a notch under the drops: 8th hats only, lighter stabs
        groove(bar, full=False, arp=True, lead_on=False, stabs=False)
        for beat in range(4):
            stab(CHORD[bar], T(bar, beat + 0.5), BEAT * 0.3, 0.2)
    whoosh_into(T(11), 0.55, 0.8)

    # ---- 11-14: CAUSE CHAOS, SURPRISE TEST: the full hook ---------------------------------------
    drums.add(T(11), crash(), 0.6)
    for bar in range(11, 15):
        groove(bar, open_hats=bar < 13)
    for bar in (13, 14):  # bouncy: pizz on the offbeat 8ths
        ci = CHORD[bar]
        for k in range(8):
            bassb.add(T(bar, k / 2 + 0.25), pizz(PROG[ci][k % 3] + 12, BEAT * 0.2), 0.22)
    drums.add(T(13), crash(1.4), 0.35)
    whoosh_into(T(15), 0.5, 0.7)

    # ---- 15-16: canteen, trailer 1's items bar ----------------------------------------------------
    for bar in (15, 16):
        ci = CHORD[bar]
        K(T(bar, 0))
        K(T(bar, 2), g=0.8)
        drums.add(T(bar, 2), clap(), 0.6)
        for k in range(8):
            drums.add(T(bar, k / 2), hat(), 0.3 if k % 2 else 0.12, pan=0.25)
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
    fx.add(T(15), riser(BAR * 2 - BEAT * 0.5), 0.4)
    roll(16, 2, ((0, 4, 0.25), (1, 3, 0.125)), 0.3)
    whoosh_into(T(17), 0.7, 0.9)

    # ---- 17-18: the lift (F, C): friends, claps on every beat -----------------------------------
    drums.add(T(17), crash(2.4), 0.6)
    for bar in (17, 18):
        groove(bar, arp=True)
        for beat in (0, 2):
            drums.add(T(bar, beat), clap(), 0.45)
        for k in range(8):
            drums.add(T(bar, k / 2 + 0.25), clap(), 0.12, pan=0.6 * (1 if k % 2 else -1))  # the gang
        hook_bar(bar, CHORD[bar], 0.1, octave=12, echo=False, pan=0.3)

    # ---- 19-21: maps build, exits, crash zoom, silence -------------------------------------------
    for bar in (19, 20):
        groove(bar, full=bar == 20, arp=True, lead_on=False, open_hats=bar == 20)
        drums.add(T(bar), crash(1.4), 0.3)
        if bar > 19:
            whoosh_into(T(bar), 0.45, 0.7)
        for k in range(4):
            lead.add(T(bar, k), chip_lead(TEASER[k] + (5 if bar == 20 else 0), BEAT * 0.4, vib=False), 0.12, pan=0.2)
    whoosh_into(T(19), 0.5, 0.8)
    ci = CHORD[21]
    for beat in range(4):
        K(T(21, beat), g=0.9)
        drums.add(T(21, beat), clap(), 0.4)
        fx.add(T(21, beat), blip(91 + beat * 2, 0.08, 0.5), 0.14, pan=0.2)  # an exit per beat
    for k in range(7):
        bassb.add(T(21, k / 2), bass(ROOTS[ci] + (12 if k % 2 else 0), BEAT * 0.45), 0.5 + 0.02 * k)
    for k in range(6):
        stab(ci, T(21, k / 2), BEAT * 0.4, 0.14 + 0.03 * k, cutoff=2000 + 800 * k)
    roll(21, 0, ((0, 4, 0.5), (2, 4, 0.25)), 0.3)
    fx.add(T(20), riser(BAR * 2 - BEAT * 0.5), 0.5)
    K(T(21, 3), big=True)  # crash zoom
    drums.add(T(21, 3), crash(0.5), 0.6)
    stab(ci, T(21, 3), BEAT * 0.45, 0.45)

    # ---- 22-23: DROP 2 -------------------------------------------------------------------------------
    drums.add(T(22), impact(), 0.9)
    OWNED["impact"].append(T(22))
    for bar in (22, 23):
        drums.add(T(bar), crash(), 0.75)
        groove(bar, arp=True, open_hats=True)
        hook_bar(bar, CHORD[bar], 0.1, octave=12, echo=False, pan=0.35)
        stab(CHORD[bar], T(bar), BEAT * 0.9, 0.3, octave=0)
    drums.add(T(23), impact(), 0.8)  # slow-mo apex
    OWNED["impact"].append(T(23))
    K(T(23), big=True, g=0.8)

    # ---- 24: escape, the win arpeggio on 24.2 --------------------------------------------------------
    groove(24, arp=False, lead_on=False, open_hats=True)
    hook_bar(24, CHORD[24], 0.2, echo=True)
    for k, m in enumerate([77, 81, 84, 89, 84, 89]):  # sfx.gd win (72 76 79 84 79 84), in F
        lead.add(T(24, 2 + k / 4), chip_lead(m, S16 * (0.9 if k < 5 else 3.5), vib=k == 5), 0.24, pan=-0.1)
    for m in [77, 81, 84, 93]:
        lead.add(T(24, 3.5), chip_lead(m, BEAT * 0.9), 0.07, pan=0.3)

    # ---- 25-26: FINAL BELL held, NEW RANK on 26.2 ------------------------------------------------
    K(T(25), big=True)
    drums.add(T(25), crash(3.0), 0.6)
    fx.add(T(25), bell_ring(2.4), 0.8)
    OWNED["bell"].append(T(25))
    l, rr = supersaw([n + 12 for n in C] + [C[0] - 12], BAR * 1.5 + 0.2, cutoff=4200, voices=7)
    e = env(len(l), 0.01, 1.2, 0.55, 0.25)
    chords.add(T(25), l * e, 0.36, pan=-0.7)
    chords.add(T(25), rr * e, 0.36, pan=0.7)
    bassb.add(T(25), bass(36, BAR * 1.5) * env(int(SR * BAR * 1.5), 0.003, 1.0, 0.4, 0.3), 0.55)
    for b in range(6):  # the clock again
        fx.add(T(25, b), tick(b % 2 == 0), 0.45, pan=0.3 if b % 2 else -0.3)
        OWNED["tick"].append(T(25, b))
    fx.add(T(25, 2), riser(T(27) - T(25, 2) - BEAT * 0.1), 0.35)
    K(T(26, 2))
    drums.add(T(26, 2), crash(1.0), 0.4)
    for k, (beat, frac) in enumerate([(2, 0), (2, 0.5), (3, 0), (3, 0.25), (3, 0.5)]):  # rank-up steps
        lead.add(T(26, beat + frac), chip_lead(79 + [0, 5, 9, 12, 17][k], BEAT * 0.4, vib=False), 0.22)
    for k in range(4):
        bassb.add(T(26, 2 + k / 2), bass(36 + (12 if k % 2 else 0), BEAT * 0.45), 0.5)
    roll(26, 2, ((0, 4, 0.25), (1, 4, 0.125)), 0.35)
    whoosh_into(T(27), 0.7, 1.0)

    # ---- 27-28: logo slam, tagline groove ----------------------------------------------------------
    drums.add(T(27), impact(), 1.0)
    OWNED["impact"].append(T(27))
    drums.add(T(27), crash(2.6), 0.9)
    groove(27)
    groove(28, arp=True)
    roll(28, 3, ((0, 4, 0.125), (0.5, 4, 0.125)), 0.3)

    # ---- 29: COMING SOON: the last chord, the bell ------------------------------------------------
    K(T(29), big=True)
    drums.add(T(29), crash(3.0), 0.8)
    l, rr = supersaw([50, 57, 62, 65, 69, 74], BAR * 1.2, cutoff=4500, voices=7)
    e = env(len(l), 0.004, 0.7, 0.35, 0.8)
    chords.add(T(29), l * e, 0.42, pan=-0.7)
    chords.add(T(29), rr * e, 0.42, pan=0.7)
    bassb.add(T(29), bass(38, BAR * 1.1) * env(int(SR * BAR * 1.1), 0.003, 0.8, 0.3, 0.6), 0.6)
    lead.add(T(29), chip_lead(86, BEAT * 1.5), 0.24)
    fx.add(T(29, 1), bell_ring(1.4), 0.45)
    OWNED["bell"].append(T(29, 1))

    # ---- accents on the act's big hits --------------------------------------------------------------
    last = -1.0
    for t, name in sorted(accents):
        if t - last < BEAT * 0.45 or any(a - 0.01 <= t < b for a, b in SILENCES) or t >= T(29):
            continue
        if any(abs(t - o) < 0.05 for o in OWNED["impact"]):
            continue
        last = t
        ci = chord_at(t + 0.01)
        if name in ("stamp", "impact", "slap"):
            stab(ci, t, BEAT * 0.35, 0.22 if name != "slap" else 0.16, octave=0)
            if name == "impact":
                drums.add(t, crash(1.2), 0.25)
        elif name == "crash":
            drums.add(t, crash(1.4), 0.3)
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


def mix_music():
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
    mix = np.stack([hp(mix[0], 28), hp(mix[1], 28)])[:, :N]
    # trailer 1's glue: a gentle tanh over the whole cue
    peak = np.max(np.abs(mix))
    mix = np.tanh(mix / peak * 1.35) / np.tanh(1.35)
    return S.prep(mix.T) * mute_mask()[:, None]


def checks(x):
    seg = lambda a, b_: S.seg(x, T(*a), T(*b_))  # noqa: E731
    sec = lambda b0, b1: seg((b0, 0), (b1, 0))  # noqa: E731
    peak = lambda a, b_: 20 * np.log10(np.abs(x[int(T(*a) * SR):int(T(*b_) * SR)]).max() + 1e-12)  # noqa: E731
    tests = [
        ("cold open (0-1) quieter than drop 1 (4-5) by 5 dB", sec(0, 2) < sec(4, 6) - 5),
        ("hush after the bell (1) 10 dB under drop 1", sec(1, 2) < sec(4, 6) - 10),
        ("drop 1 louder than the build (2-3)", sec(4, 6) > sec(2, 4) + 1.5),
        ("sneaky 6-7 quieter than drop 1 and chaos 11-12", sec(6, 8) < min(sec(4, 6), sec(11, 13)) - 2),
        ("drop 2 (22-23) is the loudest 2-bar stretch",
         sec(22, 24) >= max(sec(b_, b_ + 2) for b_ in range(0, 29) if b_ not in (21, 22, 23)) - 0.3),
        ("FINAL BELL hold (25-26.2) drops back", seg((25, 1), (26, 2)) < sec(22, 24) - 3),
        ("8.0.4-8.1 silent (peak < -80 dBFS)", peak((8, 0.4), (8, 1)) < -80),
        ("21.3.5-22.0 silent (peak < -80 dBFS)", peak((21, 3.5), (22, 0)) < -80),
        ("logo 27 louder than the ring-out 29", sec(27, 28) > sec(29, 30) + 3),
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
