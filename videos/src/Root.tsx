import React from "react";
import { Composition, continueRender, delayRender, staticFile } from "remotion";
import { Trailer } from "./film/Trailer";
import { DURATION } from "./film/cues";
import { FONT, H, W } from "./film/tokens";

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
);
