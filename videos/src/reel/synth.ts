// Deterministic pattern synth: Track + BPM -> mono samples. Pure maths (no DOM), so the browser previews the
// exact same audio the server renders into the MP4.
import { SCALES } from "./spec";
import type { Cue, Track } from "./spec";

const TAU = Math.PI * 2;
const mtof = (m: number) => 440 * Math.pow(2, (m - 69) / 12);

function rngFrom(seed: number) {
  let x = seed | 0 || 1;
  return () => {
    x ^= x << 13; x ^= x >>> 17; x ^= x << 5;
    return ((x >>> 0) / 4294967296) * 2 - 1;
  };
}

/** Semitones above the key for a scale degree (negative degrees go below). */
function semis(track: Track, deg: number) {
  const sc = SCALES[track.scale];
  const oct = Math.floor(deg / sc.length);
  return sc[((deg % sc.length) + sc.length) % sc.length] + 12 * oct;
}

export function renderTrack(track: Track, bpm: number, seconds: number, sr = 44100, loop = false, cues: Cue[] = []): Float32Array {
  const total = Math.max(1, Math.floor(seconds * sr));
  const buf = new Float32Array(total);
  const rnd = rngFrom(1337);
  const stepDur = 60 / bpm / 4;
  const stepsTotal = Math.ceil(seconds / stepDur);
  const kit = track.kit;
  const at = (n: number) => {
    const swung = n % 2 === 1 ? track.swing * stepDur : 0;
    return Math.floor((n * stepDur + swung) * sr);
  };
  const add = (i: number, v: number) => { if (i >= 0 && i < total) buf[i] += v; };

  const kick = (s0: number, vol: number) => {
    const n = Math.floor(sr * (kit === "hard" ? 0.55 : 0.32));
    let ph = 0;
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      ph += (TAU * (44 + (kit === "8bit" ? 80 : 115) * Math.exp(-t * 26))) / sr;
      let v = Math.sin(ph);
      if (kit === "8bit") v = Math.sign(v) * 0.7;
      if (kit === "hard") v = Math.tanh(v * 2.6);
      if (kit !== "lofi" && t < 0.003) v += rnd() * 0.5;
      add(s0 + i, v * Math.exp(-t * (kit === "hard" ? 5.5 : 9)) * vol);
    }
  };
  const snare = (s0: number, vol: number) => {
    const n = Math.floor(sr * 0.2);
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      const noise = rnd() * Math.exp(-t * (kit === "lofi" ? 22 : 17));
      const tone = Math.sin(TAU * 185 * t) * Math.exp(-t * 28) * 0.7;
      add(s0 + i, (kit === "8bit" ? Math.sign(noise) * Math.abs(noise) * 0.9 : noise * 0.9 + tone) * vol);
    }
  };
  const clap = (s0: number, vol: number) => {
    const n = Math.floor(sr * 0.22);
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      const burst = t < 0.03 ? 1 - ((t / 0.01) % 1) * 0.6 : 1;
      add(s0 + i, rnd() * burst * Math.exp(-t * 16) * 0.8 * vol);
    }
  };
  const hat = (s0: number, vol: number, open = false) => {
    const n = Math.floor(sr * (open ? 0.12 : 0.045));
    let prev = 0;
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      const x = rnd();
      const hp = x - prev * 0.9; prev = x;
      add(s0 + i, hp * Math.exp(-t * (open ? 22 : 75)) * 0.55 * vol);
    }
  };
  const perc = (s0: number, vol: number) => {
    const n = Math.floor(sr * 0.14);
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      const sq = (f: number) => Math.sign(Math.sin(TAU * f * t));
      add(s0 + i, (sq(540) + sq(800)) * 0.25 * Math.exp(-t * 20) * vol);
    }
  };
  const bass = (s0: number, freq: number, len: number, vol: number) => {
    let ph = 0, lp = 0;
    const cut = kit === "hard" ? 0.05 : kit === "8bit" ? 0.5 : 0.11;
    for (let i = 0; i < len; i++) {
      const t = i / sr;
      ph += freq / sr;
      const w = kit === "8bit" ? (ph % 1 < 0.5 ? 1 : -1) : 2 * (ph % 1) - 1;
      lp += (w - lp) * cut;
      const sub = Math.sin(TAU * ph);
      const env = Math.min(1, t / 0.004) * Math.min(1, (len - i) / (sr * 0.02)) * Math.exp(-t * (kit === "hard" ? 2.2 : 4));
      add(s0 + i, (lp * 0.6 + sub * 0.6) * env * vol);
    }
  };
  const lead = (s0: number, freq: number, len: number, vol: number) => {
    let ph = 0;
    for (let i = 0; i < len; i++) {
      const t = i / sr;
      ph += (freq * (1 + Math.sin(TAU * 5.5 * t) * 0.004)) / sr;
      const duty = kit === "8bit" ? 0.25 : 0.5;
      const w = ph % 1 < duty ? 1 : -1;
      const env = Math.min(1, t / 0.003) * Math.exp(-t * 7) * Math.min(1, (len - i) / (sr * 0.01));
      add(s0 + i, w * env * vol * 0.4);
    }
  };
  const chord = (s0: number, freqs: number[], len: number, vol: number, stab: boolean) => {
    const phs = freqs.flatMap((f) => [f * 0.996, f * 1.004]).map((f) => ({ f, ph: 0 }));
    let lp = 0;
    for (let i = 0; i < len; i++) {
      const t = i / sr;
      let w = 0;
      for (const o of phs) { o.ph += o.f / sr; w += 2 * (o.ph % 1) - 1; }
      w /= phs.length;
      lp += (w - lp) * (stab ? 0.22 : 0.09);
      const env = stab
        ? Math.min(1, t / 0.004) * Math.exp(-t * 14)
        : Math.min(1, t / 0.12) * Math.min(1, (len - i) / (sr * 0.2));
      add(s0 + i, lp * env * vol * 0.5);
    }
  };
  const riser = (s0: number, len: number, vol: number) => {
    let lp = 0;
    for (let i = 0; i < len; i++) {
      const u = i / len;
      lp += (rnd() - lp) * (0.02 + 0.5 * u * u);
      add(s0 + i, lp * u * u * vol * 1.6);
    }
  };

  // sync cues: the music reacts to the reel's own cuts
  const impact = (s0: number, vol: number) => {
    const n = Math.floor(sr * 0.7);
    let ph = 0, lp = 0;
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      ph += (TAU * (32 + 90 * Math.exp(-t * 14))) / sr;
      lp += (rnd() - lp) * 0.12;
      add(s0 + i, (Math.sin(ph) * Math.exp(-t * 5) + lp * Math.exp(-t * 7) * 1.4) * vol);
    }
  };
  const tick = (s0: number, vol: number) => {
    const n = Math.floor(sr * 0.06);
    for (let i = 0; i < n; i++) { const t = i / sr; add(s0 + i, Math.sin(TAU * 1320 * t) * Math.exp(-t * 60) * vol * 0.6); }
  };
  // sequenced pops (items, chips, words) are played as a rising scale so they read as a melody, not clicks
  const pluck = (s0: number, freq: number, vol: number) => {
    const n = Math.floor(sr * 0.22);
    let ph = 0;
    for (let i = 0; i < n; i++) {
      const t = i / sr;
      ph += freq / sr;
      const w = (ph % 1 < 0.5 ? 1 : -1) * 0.5 + Math.sin(TAU * ph) * 0.5;
      add(s0 + i, w * Math.min(1, t / 0.002) * Math.exp(-t * 16) * vol * 0.55);
    }
  };
  const RUN = [0, 2, 4, 7, 9, 11, 14, 16];
  if (track.syncCuts) {
    for (const c of cues) {
      const s0 = Math.floor(c.beat * (60 / bpm) * sr);
      if (c.kind === "impact") impact(s0, 0.5);
      else if (c.kind === "big") impact(s0, 0.85);
      else if (c.kind === "tick") { if (c.step !== undefined) pluck(s0, mtof(72 + track.key + semis(track, RUN[c.step % RUN.length])), 0.8); else tick(s0, 0.7); }
      else riser(s0, Math.floor((c.len ?? 2) * (60 / bpm) * sr), 0.5);
    }
  }

  const m = track.mix;
  const bars = Math.ceil(stepsTotal / 16);
  for (let bar = 0; bar < bars; bar++) {
    const building = bar < track.dropBar;
    const deg = track.prog[bar % track.prog.length] ?? 0;
    const barStart = at(bar * 16);
    const barLen = at((bar + 1) * 16) - barStart;

    // chords
    if (track.chords !== "off" && m.chords > 0) {
      const root = 48 + track.key;
      const freqs = [0, 2, 4].map((k) => mtof(root + semis(track, deg + k)));
      if (track.chords === "pad") chord(barStart, freqs, barLen, m.chords, false);
      else for (const st of [0, 3, 6, 10, 12]) if (!building || st === 0) chord(at(bar * 16 + st), freqs, Math.floor(sr * 0.16), m.chords, true);
    }
    if (track.riser && bar === track.dropBar - 1 && track.dropBar > 0) riser(barStart, barLen, 0.5);

    for (let st = 0; st < 16; st++) {
      const n = bar * 16 + st;
      const s0 = at(n);
      const d = track.drums;
      const v = m.drums;
      if (v > 0) {
        if (!building) {
          if (d.kick[st]) kick(s0, v * (d.kick[st] === 2 ? 1 : 0.85));
          if (d.snare[st]) snare(s0, v * (d.snare[st] === 2 ? 1 : 0.8));
          if (d.clap[st]) clap(s0, v * 0.8);
        }
        if (d.hat[st]) hat(s0, v * (d.hat[st] === 2 ? 1 : 0.6), st % 8 === 6 && !building);
        if (d.perc[st]) perc(s0, v * 0.7);
        if (track.fill && bar % 4 === 3 && st >= 12 && !building) snare(s0, v * (0.35 + (st - 12) * 0.18));
      }
      if (!building) {
        const b = track.bass[st];
        if (b !== null && m.bass > 0) {
          let next = 1;
          while (next < 16 - st && track.bass[st + next] === null) next++;
          bass(s0, mtof(36 + track.key + semis(track, b + deg)), Math.min(at(n + next) - s0, Math.floor(sr * 0.5)), m.bass);
        }
        const l = track.lead[st];
        if (l !== null && m.lead > 0) lead(s0, mtof(60 + track.key + semis(track, l + deg)), Math.floor(sr * stepDur * 1.6), m.lead);
      }
    }
  }

  // master: soft clip, normalise, short fade out
  let peak = 0;
  for (let i = 0; i < total; i++) { buf[i] = Math.tanh(buf[i] * 1.1); peak = Math.max(peak, Math.abs(buf[i])); }
  const g = peak > 0 ? 0.92 / peak : 1;
  const fade = loop ? 0 : Math.min(total, Math.floor(sr * 0.25));
  for (let i = 0; i < total; i++) buf[i] *= g * (fade && i > total - fade ? (total - i) / fade : 1);
  return buf;
}

/** 16-bit mono PCM WAV. */
export function encodeWav(samples: Float32Array, sr = 44100): Uint8Array {
  const out = new Uint8Array(44 + samples.length * 2);
  const dv = new DataView(out.buffer);
  const str = (o: number, s: string) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
  str(0, "RIFF"); dv.setUint32(4, 36 + samples.length * 2, true); str(8, "WAVE"); str(12, "fmt ");
  dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
  dv.setUint32(24, sr, true); dv.setUint32(28, sr * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true);
  str(36, "data"); dv.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) dv.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 32767, true);
  return out;
}
