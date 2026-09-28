// Bunk Master launch trailer: 30 s, 128 BPM, 16 bars. See videos/launch-prompt.md for the beat sheet.
import React from "react";
import { AbsoluteFill, Audio, staticFile } from "remotion";
import { useTime } from "../kit/time";
import { ACT, b, CHAPTERS, inAct, SHAKES } from "./cues";
import { clamp01, flash, shake } from "./juice";
import {
  CctvUI, ChaseUI, ClassroomUI, EscapeUI, ExcuseUI, FinalBellUI, LogoUI, MapsUI, PanicUI, PaperUI, PlanMap, RuinUI, SprayUI, Stamps, TestUI,
} from "./overlays";
import { World3D } from "./World3D";

export const Launch: React.FC<{ fps: number; debug?: boolean }> = () => {
  const t = useTime();
  const sh = shake(t, SHAKES);
  const stampBlur = Math.max(0, ...CHAPTERS.map((c) => (t >= c.words[0][1] && t < c.out + 0.15 ? 7 * clamp01((t - c.words[0][1]) / 0.1) * (1 - clamp01((t - c.out) / 0.15)) : 0)));
  const worldBlur = Math.max(stampBlur, inAct(t, ACT.test) ? 9 : 0, t >= b(13) && t < b(13, 2) ? 9 : 0);
  const white = Math.max(flash(t, b(0), 0.25) * 0.7, flash(t, b(7), 0.14) * 0.8, flash(t, b(10), 0.2) * 0.9, flash(t, b(14), 0.22) * 0.9);
  const hide3D = (t >= b(2, 1) && t < b(4) - 0.45) || inAct(t, ACT.maps);
  return (
    <AbsoluteFill style={{ background: "#2a1a0e", overflow: "hidden" }}>
      <AbsoluteFill style={{ translate: `${sh.x}px ${sh.y}px`, rotate: `${sh.r}deg`, scale: "1.04" }}>
        {hide3D ? null : <World3D t={t} blur={worldBlur} />}
        <ClassroomUI t={t} />
        <PlanMap t={t} />
        <RuinUI t={t} />
        <CctvUI t={t} />
        <ExcuseUI t={t} />
        <PaperUI t={t} />
        <SprayUI t={t} />
        <TestUI t={t} />
        <PanicUI t={t} />
        <ChaseUI t={t} />
        <MapsUI t={t} />
        <EscapeUI t={t} />
        <FinalBellUI t={t} />
        <LogoUI t={t} />
        <Stamps t={t} />
      </AbsoluteFill>
      <AbsoluteFill style={{ pointerEvents: "none", background: "radial-gradient(ellipse at center, rgba(0,0,0,0) 60%, rgba(20,10,4,.28) 100%)" }} />
      {white > 0 ? <AbsoluteFill style={{ background: "#fff", opacity: white }} /> : null}
      <Audio src={staticFile("audio/launch/mix.wav")} />
    </AbsoluteFill>
  );
};
