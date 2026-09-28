"""Bunk Master Steam trailer, score v2: punchy indie-game chiptune on real sampled instruments.

128 BPM, 24 bars, 45 s, locked to the trailer's cuts (src/steam/sfx/*.json hits, videos/steam-brief.md).
- Real instruments: MuseScore_General.sf2 (MIT) played by FluidSynth (drums, bass, brass, pizzicato, piano,
  glockenspiel, xylophone, strings, choir, orchestra hits). See audio/soundfonts/README.md.
- Chiptune on top, synthesized here: a band-limited pulse lead with vibrato and glides, 16th arps, a triangle sub.
- The hook: one 4-bar tune over the game's chase chords (Am F G E, autoload/sfx.gd), in minor for the sneaking and in
  C major for the friends and the escape.
- The trailer's SFX (every src/steam/sfx/*.json) are placed by audio/steam_music.py's engine, under the music.

Run from videos/:  uv run --python 3.12 --with numpy --with scipy --with pedalboard --with mido python audio/steam_score.py
Writes public/audio/steam/{music,sfx,mix}.wav (the files the Steam composition plays), 48.75 s, -14 LUFS, -1.5 dBTP.
"""
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import mido
import numpy as np
import pedalboard as pb

sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_music as sm  # noqa: E402  (grid, DSP helpers, SFX engine, mastering)

ROOT = sm.ROOT
SR, N, END, BEAT, BAR = sm.SR, sm.N, sm.END, sm.BEAT, sm.BAR
T, midi = sm.T, sm.midi
WORK = ROOT / "out/steam/score"
SF2 = ROOT / "audio/soundfonts/MuseScore_General.sf2"
SECONDS = N / SR

# ============================================================ notes
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def m(name):
    """'A4' -> 69, 'G#5' -> 80."""
    return NOTE[name[:-1]] + 12 * (int(name[-1]) + 1)


CH = {  # root (bass octave), chord tones
    "Am": ("A1", ["A3", "C4", "E4"]), "F": ("F1", ["F3", "A3", "C4"]), "G": ("G1", ["G3", "B3", "D4"]),
    "E": ("E1", ["E3", "G#3", "B3"]), "D": ("D2", ["D3", "F#3", "A3"]), "C": ("C2", ["C3", "E3", "G3"]),
    "Dm": ("D2", ["D3", "F3", "A3"]), "E7": ("E1", ["E3", "G#3", "D4"]),
}
# Harmony, one entry per half bar (bar, beat 0 / 2). Locked to the pictures.
HARM = {
    0: ["Am", "Am"], 1: ["Am", "Am"], 2: ["Am", "Am"], 3: ["F", "E"], 4: ["Am", "Am"], 5: ["F", "G"],
    6: ["Am", "Am"], 7: ["D", "D"], 8: ["Am", "E"], 9: ["Am", "E"], 10: ["Am", "Am"], 11: ["F", "E"],
    12: ["Am", "Am"], 13: ["F", "G"], 14: ["C", "C"], 15: ["F", "G"], 16: ["Am", "F"], 17: ["G", "E7"],
    18: ["Am", "Am"], 19: ["F", "E"], 20: ["C", "G"], 21: ["C", "G"], 22: ["F", "G"], 23: ["C", "C"],
    24: ["F", "G"], 25: ["C", "C"],
}


def chord(bar, beat):
    return CH[HARM[bar][0 if beat < 2 else 1]]


# The hook, in 16ths: (step, note, length). Same rhythm each bar: "da-da DA da da da da da".
HOOK_MIN = [
    [(0, "E5", 3), (3, "E5", 1), (4, "A5", 2), (6, "G5", 2), (8, "E5", 2), (10, "D5", 2), (12, "C5", 2), (14, "D5", 2)],
    [(0, "C5", 3), (3, "C5", 1), (4, "F5", 2), (6, "E5", 2), (8, "C5", 2), (10, "A4", 2), (12, "C5", 4)],
    [(0, "D5", 3), (3, "D5", 1), (4, "G5", 2), (6, "F5", 2), (8, "D5", 2), (10, "B4", 2), (12, "D5", 2), (14, "E5", 2)],
    [(0, "E5", 2), (2, "G#5", 2), (4, "B5", 4), (8, "G#5", 2), (10, "E5", 2), (12, "B4", 4)],
]
HOOK_MAJ = [  # the same tune, bright: over C, F, G, C
    [(0, "G5", 3), (3, "G5", 1), (4, "C6", 2), (6, "B5", 2), (8, "G5", 2), (10, "E5", 2), (12, "D5", 2), (14, "E5", 2)],
    [(0, "F5", 3), (3, "F5", 1), (4, "A5", 2), (6, "G5", 2), (8, "F5", 2), (10, "C5", 2), (12, "D5", 2), (14, "E5", 2)],
    [(0, "G5", 3), (3, "G5", 1), (4, "D6", 2), (6, "C6", 2), (8, "B5", 2), (10, "G5", 2), (12, "A5", 2), (14, "B5", 2)],
    [(0, "C6", 4), (4, "G5", 2), (6, "E5", 2), (8, "C6", 8)],
]


# ============================================================ DLS tracks
class Track:
    def __init__(self, program, perc=False):
        self.program, self.perc, self.ev = program, perc, []

    def note(self, bar, beat, beats, n, vel=100):
        n = m(n) if isinstance(n, str) else n
        self.ev.append([T(bar, beat), max(0.03, beats * BEAT), int(n), float(vel)])

    def chord(self, bar, beat, beats, notes, vel=90):
        for n in notes:
            self.note(bar, beat, beats, n, vel)


P = {  # General MIDI programs (0-based) in gs_instruments.dls
    "drums": Track(0, True), "bass": Track(33), "sbass": Track(38), "brass": Track(61), "pizz": Track(45),
    "piano": Track(0), "glock": Track(9), "xylo": Track(13), "strings": Track(48), "choir": Track(52),
    "hit": Track(55), "mgtr": Track(28), "epiano": Track(4),
}
D = P["drums"]
KICK, SNARE, CLAP, STICK, HAT, PHAT, OHAT, CRASH, RIDE, TAMB, SHAKER, WBHI, WBLO = 36, 38, 39, 37, 42, 44, 46, 49, 51, 54, 82, 76, 77
TOMS = [50, 48, 47, 45, 43, 41]
KICKS = []  # (time, strength) for the sidechain and the synth sub-kick layer
SNARES = []


def kick(bar, beat, v=118, s=1.0):
    D.note(bar, beat, 0.4, KICK, v)
    KICKS.append((T(bar, beat), s))


def snare(bar, beat, v=110, clap=True):
    D.note(bar, beat, 0.4, SNARE, v)
    if clap:
        D.note(bar, beat, 0.4, CLAP, v * 0.8)
    SNARES.append(T(bar, beat))


def hats(bar, step=0.5, v=70, beats=4.0, start=0.0, accent=True):
    x = start
    while x < beats - 1e-6:
        D.note(bar, x, 0.2, HAT, v * (1.0 if not accent or abs(x % 1 - 0.5) < 0.01 else 0.75))
        x += step


def crash(bar, beat=0, v=110):
    D.note(bar, beat, 3, CRASH, v)


# ============================================================ chip synth (numpy)
def pulse_lead(notes, duty=0.25, vib=0.006, glide=0.035, detune=7.0):
    """notes: [(t, dur, midi, vel)] -> stereo. Band-limited pulse, delayed vibrato, legato glides, a detuned double."""
    out = np.zeros((N, 2))
    notes = sorted(notes)
    prev = None
    for i, (t0, dur, n, vel) in enumerate(notes):
        k = int(dur * SR)
        tt = np.arange(k) / SR
        f = np.full(k, midi(n))
        if prev is not None and abs(prev[0] + prev[1] - t0) < 0.02:  # legato: glide from the last note
            f = midi(n) + (midi(prev[2]) - midi(n)) * np.exp(-tt / glide)
        f = f * (1 + vib * np.sin(2 * np.pi * 5.6 * tt) * np.clip((tt - 0.14) / 0.12, 0, 1))
        env = sm.adsr(k, a=0.004, d=0.18, s=0.72, r=0.04, hold=max(0.01, dur - 0.04))
        d = duty + 0.1 * np.exp(-tt * 8)  # a little "pew" on the attack
        x = sm.osc("square", f, k, duty=float(np.clip(d.mean(), 0.1, 0.5)))
        y = sm.osc("square", f * 2 ** (detune / 1200), k, duty=0.5) * 0.45
        s = np.stack([x + y * 0.6, x * 0.85 + y], 1) * env[:, None] * (vel / 127)
        sm.place(out, t0, s)
        prev = (t0, dur, n)
    return sm.lp(out, 7000)


def chip_arp(bar, beats, oct_=12, v=0.5, pattern=(0, 1, 2, 3)):
    out = []
    x = 0.0
    while x < beats - 1e-6:
        for s in range(4):
            b = x + s * 0.25
            if b >= beats:
                break
            _, tones = chord(bar, b)
            seq = [m(t) for t in tones] + [m(tones[0]) + 12]
            out.append((T(bar, b), BEAT * 0.22, seq[pattern[(int(b * 4)) % len(pattern)]] + oct_, 127 * v))
        x += 1
    return out


def pluck_voice(notes, duty=0.5, decay=14.0):
    out = np.zeros((N, 2))
    for t0, dur, n, vel in notes:
        k = int(dur * SR)
        tt = np.arange(k) / SR
        x = sm.osc("square", midi(n), k, duty=duty) * np.exp(-tt * decay) * sm.adsr(k, a=0.002, d=0.05, s=1, r=0.01, hold=dur - 0.01)
        sm.place(out, t0, sm.stereo(x * vel / 127, 0.35 if int(t0 * 8) % 2 else -0.35))
    return sm.lp(out, 5200)


def tri_sub(notes):
    out = np.zeros((N, 2))
    for t0, dur, n, vel in notes:
        k = int(dur * SR)
        x = sm.osc("tri", midi(n), k) * sm.adsr(k, a=0.003, d=0.1, s=0.9, r=0.03, hold=dur - 0.03)
        sm.place(out, t0, sm.stereo(x * vel / 127, 0))
    return out


def sub_kick():
    out = np.zeros((N, 2))
    for t0, s in KICKS:
        k = int(0.32 * SR)
        tt = np.arange(k) / SR
        x = np.sin(2 * np.pi * np.cumsum(45 + 95 * np.exp(-tt * 32)) / SR) * np.exp(-tt * 9)
        sm.place(out, t0, sm.stereo(np.tanh(x * 1.8) * s, 0))
    return out


def noise_riser(t0, t1, gain=1.0):
    k = int((t1 - t0) * SR)
    u = np.linspace(0, 1, k)
    x = sm.sweep(np.random.default_rng(3).standard_normal(k), 500 * (40 ** u), "band", q=1.2)
    out = np.zeros((N, 2))
    sm.place(out, t0, sm.stereo(x * u ** 2.2 * gain, 0))
    return out


# ============================================================ the arrangement
LEAD, ARP, PLK, SUB = [], [], [], []


def hook(bar, which, maj=False, oct_=0, vel=112, into=None):
    """One bar of the hook on the chip lead; `into` also doubles it on a DLS track."""
    for step, n, ln in (HOOK_MAJ if maj else HOOK_MIN)[which]:
        LEAD.append((T(bar, step / 4), ln * BEAT / 4 * 0.96, m(n) + oct_, vel))
        if into is not None:
            into.note(bar, step / 4, ln / 4 * 0.9, m(n) + oct_ - 12, vel * 0.8)


def bass_8ths(bar, v=100, octave=True, beats=4):
    for i in range(beats * 2):
        root, _ = chord(bar, i / 2)
        n = m(root) + (12 if octave and i % 2 else 0)
        P["bass"].note(bar, i / 2, 0.42, n + 12, v)
        SUB.append((T(bar, i / 2), BEAT * 0.45, m(root) + 12, 70))


def pad(track, bar, beat, beats, v=70, up=0):
    _, tones = chord(bar, beat)
    track.chord(bar, beat, beats, [m(t) + up for t in tones], v)


def stab(bar, beat, v=110, hit=True, brass=True):
    _, tones = chord(bar, beat)
    if hit:
        P["hit"].note(bar, beat, 1.0, m(tones[0]) + 12, v)
    if brass:
        P["brass"].chord(bar, beat, 0.45, [m(t) + 12 for t in tones], v)


def build():
    # ---- bar 0: the alarm clock. Big orchestra hit + crash on frame 0, then the classroom clock ticks.
    stab(0, 0, 124)
    crash(0, 0, 120)
    kick(0, 0, 127, 1.2)
    P["strings"].chord(0, 0, 8, [m("A2"), m("E3"), m("A3"), m("C4")], 60)
    for b in range(4):  # the clock clunks to 9:00 on 0.3
        D.note(0, b, 0.2, WBHI if b % 2 == 0 else WBLO, 90)
    stab(0, 3, 96, hit=False)
    # ---- bar 1: the HUD card builds on 8ths: pizzicato + music-box preview of the hook
    for i in range(8):
        D.note(1, i / 2, 0.2, WBHI if i % 2 == 0 else WBLO, 70 if i % 2 else 85)
        _, tones = chord(1, i / 2)
        P["pizz"].note(1, i / 2, 0.4, m(tones[i % 3]) + (12 if i >= 4 else 0), 90)
    for step, n, ln in HOOK_MIN[0][:5]:
        P["glock"].note(1, step / 4, ln / 4, m(n), 70)
    # ---- bars 2-3: classroom POV. Heartbeat kick, pizz ostinato, rising tension, stabs on the spin and RUN!
    for bar in (2, 3):
        kick(bar, 0, 100, 0.8)
        kick(bar, 0.75, 70, 0.5)
        kick(bar, 2, 100, 0.8)
        kick(bar, 2.75, 70, 0.5)
        hats(bar, 0.5, 50)
        for i in range(8):
            _, tones = chord(bar, i / 2)
            P["pizz"].note(bar, i / 2, 0.4, m(tones[[0, 2, 1, 2][i % 4]]), 80 + 5 * bar)
        P["strings"].chord(bar, 0, 4, [m(t) for t in chord(bar, 0)[1]], 50 + 10 * (bar - 2))
        SUB.append((T(bar), BAR, m(chord(bar, 0)[0]) + 12, 60))
    P["strings"].chord(3, 2, 2, [m(t) + 12 for t in chord(3, 2)[1]], 75)
    for i in range(8):  # snare build on 8ths into RUN!
        D.note(3, i / 2, 0.2, SNARE, 50 + i * 8)
    stab(3, 2, 112)  # the teacher spins
    stab(3, 3, 124)  # RUN!
    crash(3, 3, 110)
    for i, t in enumerate(TOMS[:4]):  # fill into the drop
        D.note(3, 3.5 + i * 0.125, 0.2, t, 110)
    # ---- bars 4-5: DROP 1 "SNEAK OUT OF CLASS." / "DON'T GET CAUGHT."
    for bar in (4, 5):
        crash(bar, 0, 115)
        for b in (0, 0.75, 1.5, 2, 2.75, 3.5):
            kick(bar, b, 120)
        snare(bar, 1)
        snare(bar, 3)
        hats(bar, 0.25, 72)
        D.note(bar, 0.5, 0.4, OHAT, 70)
        D.note(bar, 2.5, 0.4, OHAT, 70)
        bass_8ths(bar, 112)
        ARP.extend(chip_arp(bar, 4, 24, 0.42))
        pad(P["strings"], bar, 0, 2, 72, 12)
        pad(P["strings"], bar, 2, 2, 72, 12)
    hook(4, 0, into=P["brass"])
    hook(5, 1, into=P["brass"])
    stab(4, 0, 124)
    stab(4, 1, 108, hit=False)  # "OF CLASS."
    stab(5, 0, 124)
    stab(5, 2, 118)  # "CAUGHT."
    for i in range(4):
        D.note(5, 3 + i * 0.25, 0.2, TOMS[i + 1], 105)
    # ---- bars 6-7: DODGE, the sneaky groove (muted guitar, walking bass, side stick, shaker)
    walk = {6: ["A2", "C3", "E3", "G3"], 7: ["D3", "F#3", "A3", "C4"]}
    for bar in (6, 7):
        kick(bar, 0, 105, 0.8)
        kick(bar, 2.5, 90, 0.6)
        for b in (1, 3):
            D.note(bar, b, 0.3, STICK, 95)
        for i in range(16):
            D.note(bar, i / 4, 0.1, SHAKER, 45 + (15 if i % 2 else 0))
        for i, n in enumerate(walk[bar]):
            P["bass"].note(bar, i, 0.8, m(n), 105)
            SUB.append((T(bar, i), BEAT * 0.85, m(n), 55))
        for i in range(8):  # muted guitar chops on the upbeats, pizz on the steps (crouch-walk on the beat)
            _, tones = chord(bar, i / 2)
            if i % 2:
                P["mgtr"].chord(bar, i / 2, 0.3, [m(t) + 12 for t in tones], 85)
            else:
                P["pizz"].note(bar, i / 2, 0.3, m(tones[0]) + 12, 85)
    stab(6, 0, 120)  # DODGE
    crash(6, 0, 100)
    for i, n in enumerate(["A5", "C6", "E6"]):  # TEACHERS · GUARDS · CCTV on 8ths
        P["glock"].note(6, 1 + i * 0.5, 0.5, m(n), 95)
    PLK.extend([(T(7, 1), BEAT * 0.4, m("F#5"), 90), (T(7, 1.25), BEAT * 0.4, m("A5"), 80)])  # she glances back
    P["xylo"].chord(7, 3, 1, [m("A5"), m("D6")], 110)  # CLOSE CALL +50
    # ---- bar 8: stop-time. 8.0 hit, silence, 8.1 "Who's talking?!", 8.2 THEY HEAR HOW LOUD on 16ths
    stab(8, 0, 110)
    kick(8, 0, 110)
    stab(8, 1, 124)
    crash(8, 1, 110)
    kick(8, 1, 120, 1.1)
    for i in range(4):
        stab(8, 2 + i * 0.25, 100 + i * 6, hit=(i == 3))
        kick(8, 2 + i * 0.25, 105)
    P["strings"].chord(8, 3, 1, [m(t) for t in CH["E"][1]], 70)
    snare(8, 3.5, 90, clap=False)
    # ---- bar 9: TALK YOUR WAY OUT, groove back, [4] pressed on 9.2.5, Arjun's "!" on 9.3
    kick(9, 0, 115)
    kick(9, 2.5, 95)
    crash(9, 0, 105)
    stab(9, 0, 118)
    for b in (1, 3):
        D.note(9, b, 0.3, STICK, 100)
    for i in range(16):
        D.note(9, i / 4, 0.1, SHAKER, 50 + (15 if i % 2 else 0))
    bass_8ths(9, 100, octave=False)
    for i in range(4):  # the excuse rows on 8ths
        P["xylo"].note(9, 0.5 + i * 0.5, 0.4, m(["E5", "A5", "C6", "E6"][i]), 90)
    P["xylo"].note(9, 2.5, 0.3, m("G#6"), 115)
    stab(9, 3, 120)
    SUB.append((T(9, 3), BEAT, m("E2"), 80))
    # ---- bars 10-11: CAUSE CHAOS, the busy groove with the hook, brass hits on each gag
    for bar in (10, 11):
        crash(bar, 0, 110)
        for b in (0, 1, 2, 3):
            kick(bar, b, 118)
        kick(bar, 2.75, 90, 0.6)
        snare(bar, 1)
        snare(bar, 3)
        hats(bar, 0.25, 75)
        for b in (0.5, 1.5, 2.5, 3.5):
            D.note(bar, b, 0.4, OHAT, 60)
        bass_8ths(bar, 112)
        ARP.extend(chip_arp(bar, 4, 24, 0.35))
    hook(10, 0, into=P["brass"])
    hook(11, 1, into=P["brass"])
    for bb, bt in [(10, 0), (10, 2), (11, 0), (11, 2.75)]:  # CAUSE CHAOS, the trolley, the bonk, the +140
        stab(bb, bt, 120)
    stab(11, 2, 110, hit=False)  # the spray
    for i in range(6):  # siren figure on the FIRE ALARM, up into the white-out
        LEAD.append((T(11, 3 + i * 1 / 6), BEAT / 6 * 0.95, m("E6") + (3 if i % 2 else 0) + i, 100))
    # ---- bars 12-13: SURPRISE TEST: bouncy xylophone, papers dealt on 12.1/12.2/12.3, canteen buys on 8ths
    for bar in (12, 13):
        kick(bar, 0, 112)
        kick(bar, 1.5, 90)
        kick(bar, 2, 108)
        snare(bar, 1, 100, clap=False)
        snare(bar, 3, 100, clap=False)
        hats(bar, 0.5, 70)
        for i in range(8):
            root, tones = chord(bar, i / 2)
            P["bass"].note(bar, i / 2, 0.35, m(root) + 12 + (7 if i % 2 else 0), 105)
        pad(P["epiano"], bar, 0, 2, 70, 12)
        pad(P["epiano"], bar, 2, 2, 70, 12)
    stab(12, 0, 120)
    crash(12, 0, 105)
    for b, n in [(1, "A5"), (2, "C6"), (3, "E6")]:  # three papers
        P["xylo"].chord(12, b, 0.5, [m(n), m(n) + 12], 110)
    for i, n in enumerate(["C6", "D6", "E6", "G6", "A6", "C7"]):  # the sort clicks on 32nds -> "Sorted!"
        P["xylo"].note(12, 3 + i / 8, 0.12, m(n) - 12, 95)
    stab(13, 0, 118)  # the merit badge
    P["glock"].chord(13, 0, 1.5, [m("C6"), m("E6"), m("A6")], 110)
    for i in range(5):  # canteen: buys on 8ths
        P["glock"].note(13, 1 + i * 0.5, 0.4, m(["G5", "A5", "B5", "C6", "D6"][i]), 95)
    for i in range(4):
        D.note(13, 3.5 + i * 0.125, 0.2, SNARE, 80 + i * 10)
    # ---- bars 14-15: PLAY WITH UP TO 8 FRIENDS: the lift. C major, claps, tambourine, one glock note per friend
    for bar in (14, 15):
        kick(bar, 0, 115)
        kick(bar, 2, 110)
        kick(bar, 2.75, 85)
        for b in (1, 3):
            D.note(bar, b, 0.4, CLAP, 115)
            D.note(bar, b + 0.02, 0.4, CLAP, 95)
            SNARES.append(T(bar, b))
        for i in range(8):
            D.note(bar, i / 2, 0.3, TAMB, 70 if i % 2 else 55)
        hats(bar, 0.25, 55)
        bass_8ths(bar, 105)
        P["piano"].chord(bar, 0, 0.45, [m(t) + 12 for t in chord(bar, 0)[1]], 95)
        for b in (0.5, 1.5, 2.5, 3.5):
            P["piano"].chord(bar, b, 0.35, [m(t) + 12 for t in chord(bar, b)[1]], 80)
        pad(P["strings"], bar, 0, 2, 70, 12)
        pad(P["strings"], bar, 2, 2, 70, 12)
    crash(14, 0, 110)
    stab(14, 0, 116)
    for i, n in enumerate(["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"]):  # 8 friends land on 8ths
        P["glock"].note(14, i / 2, 0.5, m(n), 100)
        PLK.append((T(14, i / 2), BEAT * 0.4, m(n), 95))
    hook(15, 1, maj=True, into=P["brass"])
    stab(15, 0, 118)  # UP TO 8 FRIENDS
    P["choir"].chord(15, 0, 4, [m("C4"), m("F4"), m("A4")], 70)
    P["glock"].chord(15, 3, 0.5, [m("G6"), m("B6"), m("D7")], 110)  # poses
    # ---- bars 16-17: ESCAPE THE WHOLE UNIVERSITY: the build
    for i in range(4):
        kick(16, i, 110)
    for i in range(8):
        kick(17, i / 2, 100 + i * 3)
    for bar in (16, 17):
        bass_8ths(bar, 110, octave=False)
        hats(bar, 0.5 if bar == 16 else 0.25, 70)
        ARP.extend(chip_arp(bar, 4, 24, 0.3 + 0.1 * (bar - 16)))
        pad(P["strings"], bar, 0, 2, 80, 12)
        pad(P["strings"], bar, 2, 2, 85, 12)
    snare(16, 1, 95, clap=False)
    snare(16, 3, 95, clap=False)
    for i in range(16):  # snare roll through bar 17
        D.note(17, i / 4, 0.15, SNARE, 60 + i * 4)
    crash(16, 0, 110)
    stab(16, 0, 118)
    stab(16, 0.5, 110, hit=False)  # WHOLE UNIVERSITY
    P["xylo"].chord(16, 3, 0.8, [m("E6"), m("A6")], 110)  # FIRST DAY's way out
    stab(17, 0, 118)  # GRAND CAMPUS
    for i, n in enumerate(["C6", "D6", "E6", "G6"]):  # the 4 ways out on 8ths
        P["glock"].note(17, 1 + i * 0.5, 0.5, m(n), 105)
    for i in range(4):
        LEAD.append((T(17, 1 + i * 0.5), BEAT * 0.45, m(["C5", "D5", "E5", "G5"][i]), 90))
    stab(17, 3, 124)  # crash zoom on the gate
    kick(17, 3, 127, 1.2)
    # ---- bars 18-19: DROP 2, the chase. The whole hook, big. 18.3: the slow-mo vault, apex (and a slam) on 19.0.
    crash(18, 0, 127)
    stab(18, 0, 127)
    for b in (0, 0.75, 1.5, 2, 2.75):
        kick(18, b, 124, 1.1)
    snare(18, 1)
    snare(18, 3, 90, clap=False)
    hats(18, 0.25, 80, beats=3)
    bass_8ths(18, 118, beats=3)
    ARP.extend(chip_arp(18, 3, 24, 0.45))
    hook(18, 0, into=P["brass"])
    hook(18, 0, oct_=-12, vel=90)
    P["strings"].chord(18, 0, 3, [m("A4"), m("C5"), m("E5")], 90)
    P["choir"].chord(18, 0, 3, [m("A3"), m("E4"), m("A4")], 80)
    P["strings"].chord(18, 3, 1, [m("E4"), m("G#4"), m("B4"), m("E5")], 100)  # the slow-mo swell
    crash(19, 0, 127)
    stab(19, 0, 127)
    kick(19, 0, 127, 1.3)
    for b in (1.5, 2, 2.75, 3.5):
        kick(19, b, 120)
    snare(19, 1)
    snare(19, 3)
    hats(19, 0.25, 80)
    bass_8ths(19, 118)
    ARP.extend(chip_arp(19, 4, 24, 0.45))
    hook(19, 1, into=P["brass"])
    hook(19, 1, oct_=-12, vel=90)
    stab(19, 1.75, 116, brass=False)  # the faceplant
    P["strings"].chord(19, 0, 2, [m("F4"), m("A4"), m("C5")], 90)
    P["strings"].chord(19, 2, 2, [m("E4"), m("G#4"), m("B4")], 95)
    for i in range(4):
        D.note(19, 3.5 + i * 0.125, 0.2, TOMS[i], 115)
    # ---- bar 20: triumph in C major: out of the gate, the escape banner (20.2) with the game's win arpeggio
    crash(20, 0, 115)
    for b in (0, 1, 2, 3):
        kick(20, b, 116)
    snare(20, 1)
    snare(20, 3)
    hats(20, 0.25, 72)
    for b in (0.5, 1.5, 2.5, 3.5):
        D.note(20, b, 0.4, OHAT, 65)
    bass_8ths(20, 110)
    pad(P["strings"], 20, 0, 2, 85, 12)
    pad(P["strings"], 20, 2, 2, 85, 12)
    pad(P["choir"], 20, 0, 4, 70)
    hook(20, 0, maj=True, into=P["brass"])
    for i, n in enumerate([72, 76, 79, 84, 79, 84]):
        PLK.append((T(20, 2 + i * 0.25), BEAT * 0.24, n + 12, 110))
    stab(20, 0, 124)
    # ---- bars 21-22.2: FINAL BELL, held long enough to read. A lighter groove under it.
    for bar in (21, 22):
        kick(bar, 0, 108)
        kick(bar, 2, 100)
        for b in (1, 3):
            D.note(bar, b, 0.4, CLAP, 100)
            SNARES.append(T(bar, b))
        for i in range(8):
            D.note(bar, i / 2, 0.3, TAMB, 60 if i % 2 else 48)
        bass_8ths(bar, 95, octave=False)
        pad(P["strings"], bar, 0, 2, 75, 12)
        pad(P["strings"], bar, 2, 2, 78, 12)
    crash(21, 0, 110)
    stab(21, 0, 118)
    P["glock"].chord(21, 0, 2, [m("C6"), m("E6"), m("G6")], 105)  # FINAL BELL!
    for i, n in enumerate(["C5", "E5", "G5", "C6", "E6"]):  # the rows on 8ths
        P["xylo"].note(21, i * 0.5, 0.4, m(n), 88)
    for i, n in enumerate(["G5", "B5", "D6"]):  # the awards on 8ths
        P["glock"].note(21, 2.5 + i * 0.5, 0.5, m(n), 95)
    hook(21, 0, maj=True, vel=85)
    for i, n in enumerate(["F5", "G5", "A5", "C6"]):  # XP bar + rank flip
        P["glock"].note(22, i * 0.25, 0.25, m(n), 90)
    P["epiano"].chord(22, 0, 2, [m("F4"), m("A4"), m("C5")], 75)  # the hold
    stab(22, 2, 124)  # NEW RANK: BUNK MASTER
    crash(22, 2, 115)
    kick(22, 2, 124, 1.1)
    P["choir"].chord(22, 2, 2, [m("G4"), m("B4"), m("D5")], 100)
    P["glock"].chord(22, 2, 1, [m("G6"), m("B6"), m("D7")], 105)
    for i in range(6):
        D.note(22, 3.25 + i / 8, 0.2, TOMS[i], 110)
    # ---- bars 23-25: the logo. Slam on 23.0, a gentle pulse under the tagline and chips, COMING SOON on 25.0.
    crash(23, 0, 127)
    stab(23, 0, 127)
    kick(23, 0, 127, 1.4)
    stab(23, 0.5, 116, hit=False)  # MASTER
    P["strings"].chord(23, 0, 8, [m("C3"), m("G3"), m("C4"), m("E4"), m("G4")], 90)
    P["choir"].chord(23, 0, 6, [m("C4"), m("E4"), m("G4"), m("C5")], 80)
    SUB.append((T(23), BAR * 2, m("C2"), 95))
    for bar in (23, 24):  # the pulse: soft kick on the beat, shaker, bass on the root
        for b in range(4):
            if bar == 23 and b < 2:
                continue
            kick(bar, b, 80, 0.4)
        for i in range(8 if bar == 24 else 4):
            D.note(bar, (4 - (8 if bar == 24 else 4) / 2) + i / 2, 0.15, SHAKER, 50)
    P["bass"].note(24, 0, 1.8, m("F2"), 90)
    P["bass"].note(24, 2, 1.8, m("G2"), 90)
    P["strings"].chord(24, 0, 2, [m("F3"), m("A3"), m("C4"), m("F4")], 75)
    P["strings"].chord(24, 2, 2, [m("G3"), m("B3"), m("D4"), m("G4")], 80)
    tag = [(23, 2, "G5"), (23, 2.5, "G5"), (23, 3, "C6"), (23, 3.5, "B5"),  # "Sneak out of class."
           (24, 0, "A5"), (24, 0.5, "G5"), (24, 1.5, "E5")]  # "Don't get ... caught."
    for bar, beat, n in tag:  # the hook's head, one note per word
        P["glock"].note(bar, beat, 0.5, m(n), 88)
        LEAD.append((T(bar, beat), BEAT * 0.45, m(n) - 12, 70))
    for i, n in enumerate(["C6", "D6", "E6"]):  # the chips on 8ths
        P["xylo"].note(24, 2 + i * 0.5, 0.4, m(n), 90)
    for i in range(4):
        D.note(24, 3.5 + i * 0.125, 0.2, SNARE, 60 + i * 12)
    crash(25, 0, 110)
    stab(25, 0, 116)  # COMING SOON
    kick(25, 0, 116, 1.0)
    P["piano"].chord(25, 0, 4, [m("C4"), m("E4"), m("G4"), m("C5")], 85)
    P["strings"].chord(25, 0, 4, [m("C3"), m("G3"), m("C4"), m("E4")], 80)
    SUB.append((T(25), BAR, m("C2"), 90))
    for step, n, ln in HOOK_MAJ[3]:  # the tune's last phrase, ringing out
        P["glock"].note(25, 0.25 + step / 4, ln / 4, m(n), 78)
    P["glock"].chord(25, 1, 3, [m("G6"), m("C7")], 72)  # WISHLIST NOW


# ============================================================ render + mix
def write_midi(path, tr):
    """One track as a type-0 MIDI file at 128 BPM (percussion on channel 10)."""
    mf = mido.MidiFile(type=0, ticks_per_beat=960)
    trk = mido.MidiTrack()
    mf.tracks.append(trk)
    ch = 9 if tr.perc else 0
    trk.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(sm.BPM)))
    if not tr.perc:
        trk.append(mido.Message("program_change", program=tr.program, channel=ch))
    tick = lambda sec: int(round(sec / BEAT * 960))
    msgs = []
    for t0, dur, n, v in tr.ev:
        msgs.append((tick(t0), 1, n, int(max(1, min(127, v)))))
        msgs.append((tick(t0 + dur), 0, n, 0))
    msgs.sort(key=lambda x: (x[0], x[1]))
    now = 0
    for tk, on, n, v in msgs:
        trk.append(mido.Message("note_on" if on else "note_off", note=n, velocity=v, channel=ch, time=tk - now))
        now = tk
    mf.save(path)


def render_track(name, tr):
    """FluidSynth + MuseScore_General.sf2, dry (no built-in reverb/chorus: the mix adds its own)."""
    if not tr.ev:
        return name, np.zeros((N, 2))
    mid, w = WORK / f"{name}.mid", WORK / f"{name}.wav"
    write_midi(mid, tr)
    subprocess.run(["fluidsynth", "-ni", "-q", "-R", "0", "-C", "0", "-g", "0.5", "-r", str(SR), "-F", str(w), str(SF2), str(mid)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    x = pb.io.AudioFile(str(w)).read(int(SECONDS * SR)).T.astype(np.float64)
    if len(x) < N:
        x = np.vstack([x, np.zeros((N - len(x), 2))])
    x = x[:N]
    # Samples with a slow attack (finger bass, muted guitar) speak late: measure the median onset lag against the
    # note times and pull the stem earlier by it, so everything lands on the grid.
    env = np.abs(x).max(1)
    lags = []
    for t0, *_ in sorted(tr.ev)[:80]:
        i = int(t0 * SR)
        seg = env[max(0, i - 400):i + 2000]
        if seg.max() > 1e-3:
            lags.append(np.argmax(seg > 0.25 * seg.max()) - 400)
    lag = int(np.median(lags)) if lags else 0
    if lag > int(0.002 * SR):
        x = np.vstack([x[lag:], np.zeros((lag, 2))])
    return name, x


def pan(x, p):
    """Re-pan a (near-mono) stem: p in -1..1."""
    mono = x.mean(1)
    return sm.stereo(mono, p)


def widen(x, amount=1.6):
    mid, side = (x[:, 0] + x[:, 1]) / 2, (x[:, 0] - x[:, 1]) / 2
    return np.stack([mid + side * amount, mid - side * amount], 1)


def fx(x, chain):
    return pb.Pedalboard(chain)(x.T.astype(np.float32), SR).T.astype(np.float64)


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    build()
    with ThreadPoolExecutor(6) as ex:
        S = dict(ex.map(lambda kv: render_track(*kv), P.items()))
    print("  rendered", ", ".join(f"{k}({len(v.ev)})" for k, v in P.items()))

    # sidechain curves from the kicks
    sm.KICKS[:] = KICKS
    duck = sm.duck_curve(0.55, 0.08)[:, None]
    duck_soft = sm.duck_curve(0.3, 0.1)[:, None]

    drums = fx(S["drums"], [pb.HighpassFilter(30), pb.Compressor(threshold_db=-16, ratio=3, attack_ms=8, release_ms=90),
                            pb.Gain(4)])
    drums = drums + sub_kick() * 0.55
    bass = fx(S["bass"] * 1.0 + S["sbass"] * 0.0, [pb.HighpassFilter(35), pb.Compressor(threshold_db=-18, ratio=4, attack_ms=5, release_ms=80),
                                                   pb.Distortion(drive_db=6), pb.LowpassFilter(2800), pb.Gain(2)])
    bass = (bass + tri_sub(SUB) * 0.35) * duck
    lead = pulse_lead(LEAD)
    lead = fx(lead, [pb.HighpassFilter(180), pb.Compressor(threshold_db=-14, ratio=3), pb.Gain(-2)])
    lead_fx = fx(lead, [pb.Delay(delay_seconds=0.75 * BEAT, feedback=0.32, mix=1.0), pb.LowpassFilter(4500)]) * 0.28
    arp = fx(pluck_voice(ARP, duty=0.25), [pb.HighpassFilter(300), pb.Chorus(rate_hz=0.8, depth=0.2, mix=0.3)]) * duck_soft
    plk = pluck_voice(PLK, duty=0.5, decay=9)
    brass = fx(pan(S["brass"], -0.15) + pan(S["brass"], 0.15) * 0.0, [pb.HighpassFilter(120), pb.Compressor(threshold_db=-18, ratio=3), pb.Gain(2)]) * duck_soft
    hits = fx(S["hit"], [pb.HighpassFilter(60), pb.Gain(1)])
    keys = fx(pan(S["piano"], 0.25) + pan(S["epiano"], 0.3) * 0.8 + pan(S["pizz"], -0.4) * 1.2 + pan(S["mgtr"], 0.45) * 0.9, [pb.HighpassFilter(140), pb.Compressor(threshold_db=-20, ratio=2.5)]) * duck_soft
    bells = fx(pan(S["glock"], 0.35) + pan(S["xylo"], -0.35) * 1.1, [pb.HighpassFilter(300), pb.Gain(1)])
    pads = widen(pan(S["strings"], -0.3) + pan(S["choir"], 0.3) * 0.8, 1.3)
    pads = fx(pads, [pb.HighpassFilter(120), pb.Chorus(rate_hz=0.4, depth=0.25, mix=0.4)]) * duck

    dry = {
        "drums": drums * 1.0, "bass": bass * 0.95, "lead": lead * 1.15, "arp": arp * 0.55, "plk": plk * 0.6,
        "brass": brass * 0.9, "hits": hits * 0.75, "keys": keys * 0.85, "bells": bells * 0.75, "pads": pads * 0.7,
    }
    send = dry["lead"] * 0.25 + dry["brass"] * 0.2 + dry["keys"] * 0.25 + dry["bells"] * 0.35 + dry["pads"] * 0.4 + dry["hits"] * 0.3 + dry["drums"] * 0.06
    room = fx(send, [pb.Reverb(room_size=0.62, damping=0.45, wet_level=1.0, dry_level=0.0, width=1.0), pb.HighpassFilter(220), pb.LowpassFilter(7000)])
    music = sum(dry.values()) + widen(room, 1.5) * 0.55 * duck_soft + widen(lead_fx, 1.8)
    music = music + noise_riser(T(1, 2), T(2), 0.12) + noise_riser(T(3), T(3, 3), 0.18) + noise_riser(T(9, 3), T(10), 0.15) \
        + noise_riser(T(11, 3), T(12), 0.2) + noise_riser(T(16), T(17, 3.5), 0.3) + noise_riser(T(21, 3), T(22), 0.2)
    # the slow-mo vault (18.3 -> 19.0): the band falls away under a swell; the drums stop
    a, b_ = int(T(18, 3) * SR), int(T(19) * SR)
    ramp = np.linspace(1, 0.25, b_ - a) ** 1.5
    for k in ("drums", "bass", "arp"):
        pass
    music[a:b_] *= np.clip(ramp[:, None] + 0.0, 0, 1)
    music = fx(music, [pb.Compressor(threshold_db=-12, ratio=2, attack_ms=20, release_ms=200)])
    music = sm.shelf(sm.shelf(music, 50, -2.0, "low"), 6000, 1.5, "high")

    # the written silences (music only; SFX inside still play)
    sm.SILENCES[:] = [(T(8, 0.3), T(8, 1), 0.04, 0.002), (T(17, 3.5), T(18), 0.004, 0.001)]
    sm.OWNED.clear()
    mute = sm.mute_windows()
    music = sm.prep(music) * mute[:END]
    music *= 10 ** ((sm.TARGET_LUFS - sm.lufs(music)) / 20)

    print("placing SFX...")
    small, big, log = sm.build_sfx()
    mdb = sm.short_db(music)
    small, _ = sm.keyed(sm.prep(small + sm.reverb(small * 0.3) * mute), mdb, -9.0, -26.0)
    big, _ = sm.keyed(sm.prep(big + sm.reverb(big * 0.3) * mute), mdb, -1.5, -18.0)
    sfx = small + big
    out = ROOT / "public/audio/steam"
    mm, _, gr_m = sm.master(music)
    mix, g, gr_x = sm.master(music + sfx)
    s = sfx * g
    sm.write(out / "music.wav", mm)
    sm.write(out / "sfx.wav", s)
    sm.write(out / "mix.wav", mix)
    sm.report("music.wav", mm, gr_m)
    sm.report("mix.wav", mix, gr_x)


if __name__ == "__main__":
    main()
