// Bunk Master Steam trailer: 56.25 s, 128 BPM, 30 bars. Brief: videos/steam-brief.md.
// Each act owns its window in LOCAL time (cues.ts ACTS) and is shifted onto the film by OFFSET bars.
import React from "react";
import { AbsoluteFill, Audio, staticFile } from "remotion";
import { useTime } from "../kit/time";
import { Chaos } from "./acts/Chaos";
import { Crew } from "./acts/Crew";
import { Dodge } from "./acts/Dodge";
import { Finale } from "./acts/Finale";
import { Open } from "./acts/Open";
import { ACTS, BAR, OFFSET, type ActName } from "./cues";

const ORDER: [ActName, React.FC<{ t: number }>][] = [["open", Open], ["dodge", Dodge], ["chaos", Chaos], ["crew", Crew], ["finale", Finale]];

export const Steam: React.FC<{ fps: number; debug?: boolean; muted?: boolean }> = ({ muted }) => {
  const t = useTime();
  return (
    <AbsoluteFill style={{ background: "#2a1a0e", overflow: "hidden" }}>
      {ORDER.map(([name, Act]) => {
        const local = t - OFFSET[name] * BAR;
        const [a, z] = ACTS[name];
        return local >= a && local < z ? <Act key={name} t={local} /> : null;
      })}
      {muted ? null : <Audio src={staticFile("audio/steam/mix.wav")} />}
    </AbsoluteFill>
  );
};
