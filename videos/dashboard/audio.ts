import { useEffect, useRef, useState } from "react";
import { cueList, durationSeconds, ReelSpec, Track } from "../src/reel/spec";
import { encodeWav, renderTrack } from "../src/reel/synth";

const toUrl = (samples: Float32Array) => URL.createObjectURL(new Blob([encodeWav(samples) as BlobPart], { type: "audio/wav" }));

/** Blob URL of the custom music for the whole reel, rebuilt (debounced) when the track, tempo or length changes. */
export function useTrackUrl(spec: ReelSpec) {
  const [url, setUrl] = useState<string>();
  const key = spec.music === "custom" && spec.track ? JSON.stringify([spec.track, spec.bpm, Math.ceil(durationSeconds(spec) * 10), cueList(spec)]) : "";
  useEffect(() => {
    if (!key) { setUrl(undefined); return; }
    const t = setTimeout(() => {
      const u = toUrl(renderTrack(spec.track!, spec.bpm, durationSeconds(spec) + 0.3, 44100, false, cueList(spec)));
      setUrl((old) => { if (old) URL.revokeObjectURL(old); return u; });
    }, 350);
    return () => clearTimeout(t);
  }, [key]); // eslint-disable-line
  return url;
}

/** Loops the groove (no build, no riser) so it can be auditioned while editing the patterns. */
export function useLoopPreview(track: Track | undefined, bpm: number) {
  const [playing, setPlaying] = useState(false);
  const audio = useRef<HTMLAudioElement | null>(null);
  const urlRef = useRef<string | undefined>(undefined);
  const key = JSON.stringify([track, bpm]);
  useEffect(() => {
    if (!playing || !track) return;
    const t = setTimeout(() => {
      const bars = Math.max(2, track.prog.length);
      const secs = bars * 16 * (60 / bpm / 4);
      const u = toUrl(renderTrack({ ...track, dropBar: 0, riser: false, fill: false }, bpm, secs, 44100, true));
      const a = audio.current ?? (audio.current = new Audio());
      a.loop = true; a.src = u;
      a.play().catch(() => {});
      if (urlRef.current) URL.revokeObjectURL(urlRef.current);
      urlRef.current = u;
    }, 250);
    return () => clearTimeout(t);
  }, [playing, key]); // eslint-disable-line
  useEffect(() => { if (!playing) audio.current?.pause(); }, [playing]);
  useEffect(() => () => { audio.current?.pause(); }, []);
  return { playing, toggle: () => setPlaying((p) => !p) };
}
