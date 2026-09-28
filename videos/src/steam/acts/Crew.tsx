// Act "crew" (local bars 14-19): see src/steam/cues.ts ACTS.crew and videos/steam-brief.md.
// 14-15 PLAY WITH / UP TO 8 FRIENDS: the 3D lobby lineup (crew/Lineup.tsx).
// 16 ESCAPE THE WHOLE UNIVERSITY + FIRST DAY (three steps, one per beat); 17 GRAND CAMPUS builds; 18 its four
// ways out on 8ths, held, crash zoom on 18.3, freeze + iris to ink on 18.3.5 for the drop at 19.0 (crew/Maps.tsx).
import React from "react";
import { ACTS, b, within } from "../cues";
import { Lineup } from "../crew/Lineup";
import { Maps } from "../crew/Maps";

export const Crew: React.FC<{ t: number }> = ({ t }) => {
  if (!within(t, ACTS.crew)) return null;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#2a1a0e" }}>
      {t < b(16) ? <Lineup t={t} /> : <Maps t={t} />}
    </div>
  );
};
