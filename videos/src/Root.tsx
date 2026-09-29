import React from "react";
import { Composition, continueRender, delayRender, staticFile } from "remotion";
import { Trailer } from "./film/Trailer";
import { Launch } from "./launch/Launch";
import { Steam } from "./steam/Steam";
import { DURATION as STEAM_DURATION } from "./steam/cues";
import { DURATION as LAUNCH_DURATION } from "./launch/cues";
import { DURATION } from "./film/cues";
import { FONT, H, W } from "./film/tokens";
import { Reel } from "./reel/Reel";
import { FORMATS, FPS, SAMPLE, ReelSpec, durationFrames, sanitize } from "./reel/spec";

// The game's pixel font (fonts/Jersey10-Regular.ttf, SIL OFL), loaded before the first frame.
const fontHandle = typeof window !== "undefined" ? delayRender("font") : null;
if (typeof window !== "undefined") {
  const face = new FontFace(FONT, `url(${staticFile("fonts/Jersey10-Regular.ttf")})`);
  face
    .load()
    .then((loaded) => {
      document.fonts.add(loaded);
      if (fontHandle !== null) continueRender(fontHandle);
    })
    .catch(() => fontHandle !== null && continueRender(fontHandle));
}

type Props = { fps: number };

export const Root: React.FC = () => (
  <>
  <Composition
    id="Reel"
    component={Reel}
    width={FORMATS["9:16"].width}
    height={FORMATS["9:16"].height}
    fps={FPS}
    durationInFrames={durationFrames(SAMPLE)}
    defaultProps={{ spec: SAMPLE } as { spec: ReelSpec; audioSrc?: string }}
    calculateMetadata={({ props }) => {
      const spec = sanitize(props.spec);
      return { width: FORMATS[spec.format].width, height: FORMATS[spec.format].height, durationInFrames: durationFrames(spec), props: { ...props, spec } };
    }}
  />
  <Composition
    id="Steam"
    component={Steam}
    width={W}
    height={H}
    fps={60}
    durationInFrames={Math.round(STEAM_DURATION * 60)}
    defaultProps={{ fps: 60, muted: true } as { fps: number; muted: boolean }}
    calculateMetadata={({ props }) => ({
      fps: props.fps,
      durationInFrames: Math.round(STEAM_DURATION * props.fps),
    })}
  />
  <Composition
    id="Launch"
    component={Launch}
    width={W}
    height={H}
    fps={60}
    durationInFrames={Math.round(LAUNCH_DURATION * 60)}
    defaultProps={{ fps: 60 } as Props}
    calculateMetadata={({ props }) => ({
      fps: props.fps,
      durationInFrames: Math.round(LAUNCH_DURATION * props.fps),
    })}
  />
  <Composition
    id="Trailer"
    component={Trailer}
    width={W}
    height={H}
    fps={60}
    durationInFrames={Math.round(DURATION * 60)}
    defaultProps={{ fps: 60 } as Props}
    calculateMetadata={({ props }) => ({
      fps: props.fps,
      durationInFrames: Math.round(DURATION * props.fps),
    })}
  />
  </>
);
