// Act "finale" (bars 18-24): the chase (DROP 2), the escape and the final bell, then the logo end card.
// See src/steam/cues.ts ACTS.finale and videos/steam-brief.md. Pieces live in src/steam/finale/.
import React from "react";
import { ACTS, b, within } from "../cues";
import { ChaseOverlay, ChaseWorld, chaseShake } from "../finale/chase";
import { LogoOverlay, LogoWorld, logoShake } from "../finale/logo";
import { EscapeOverlay, EscapeWorld, escapeShake, FinalBell } from "../finale/escape";

export const Finale: React.FC<{ t: number }> = ({ t }) => {
  if (!within(t, ACTS.finale)) return null;
  if (t < b(20)) {
    const s = chaseShake(t);
    return (
      <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#8dd0ef" }}>
        <div style={{ position: "absolute", inset: 0, translate: `${s.x}px ${s.y}px`, rotate: `${s.r}deg`, scale: "1.05" }}>
          <ChaseWorld t={t} />
          <ChaseOverlay t={t} />
        </div>
      </div>
    );
  }
  if (t < b(22, 3.5)) {
    const s = escapeShake(t);
    const dim = t >= b(21) - 0.05 ? Math.min(1, (t - b(21) + 0.05) / 0.1) : 0;
    return (
      <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#8dd0ef" }}>
        <div style={{ position: "absolute", inset: 0, translate: `${s.x}px ${s.y}px`, rotate: `${s.r}deg`, scale: "1.05" }}>
          <EscapeWorld t={t} blur={9 * dim} />
          <EscapeOverlay t={t} />
          <FinalBell t={t} />
        </div>
      </div>
    );
  }
  const s = logoShake(t);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#8dd0ef" }}>
      <div style={{ position: "absolute", inset: 0, translate: `${s.x}px ${s.y}px`, rotate: `${s.r}deg`, scale: "1.04" }}>
        <LogoWorld t={t} />
        <LogoOverlay t={t} />
      </div>
    </div>
  );
};
