// Who stands where, doing what, at time t. Pure functions shared by the 3D world and the overlays.
import { step } from "../kit/spring";
import { ACT, b, BEAT, inAct } from "./cues";
import { clamp01, POP, SNAP, WOBBLE } from "./juice";
import { seat } from "./sets";
import { CAST, HIP_HEIGHT, mixPose, REST, sitPose, walkPose, type Look, type Pose, type V3 } from "./voxel";

export type Actor = {
  id: string; look: Look; pose: Pose; p: V3; yaw: number; roll?: number; pitch?: number; squash?: number;
  chai?: boolean;
};

const PI = Math.PI;
const sp = (t: number, at: number, cfg = POP) => step(t - at, cfg);
const seated = (id: string, look: Look, s: V3, extra: Partial<Actor> = {}, headY = 0): Actor => ({
  id, look, pose: { ...sitPose(1), headY }, p: [s[0], 0, s[2]], yaw: PI, ...extra,
});

/** Where the top of an actor's head is (for "!" marks and bubbles). */
export const headTop = (a: Actor): V3 => [a.p[0], a.p[1] + (a.pose.hipY + 0.56 + 0.5) * (a.squash ?? 1), a.p[2]];

// Teacher writing on the board: arm up, small chalk strokes on 16ths.
const writing = (t: number): Pose => ({ ...REST, armRX: 2.1 + 0.12 * Math.sin(t * 2 * PI / (BEAT / 2)), armRZ: -0.25, headX: -0.15 });

export function actors(t: number): Actor[] {
  // ---------------- classroom, bars 0-2
  if (t < b(2, 0.5)) {
    const hero = seated("hero", CAST.hero, seat(3, 0));
    // Sneaky glances on beats 2 and 3, back to front on bar 1.
    hero.pose.headY = 0.55 * (sp(t, b(0, 2), WOBBLE) - sp(t, b(0, 3), WOBBLE)) - 0.5 * (sp(t, b(0, 3), WOBBLE) - sp(t, b(1), WOBBLE));
    // Bar 1 beat 3: a nod.
    hero.pose.headX = -0.35 * (sp(t, b(1, 3), SNAP) - sp(t, b(1, 3.5), SNAP));
    // Friends turn to the hero one per beat on bar 1.
    const fa = seated("friendA", CAST.friendA, seat(2, 1));
    fa.pose.headY = -0.9 * sp(t, b(1, 0), WOBBLE);
    const fc = seated("friendC", CAST.friendC, seat(1, 0));
    fc.yaw = PI + 2.3 * sp(t, b(1, 1), WOBBLE);
    fc.pose.headY = 0.3 * sp(t, b(1, 1), WOBBLE);
    const fb = seated("friendB", CAST.friendB, seat(5, 0));
    fb.pose.headY = 0.2 * sp(t, b(1, 2), WOBBLE);
    fb.pose.headX = 0.25 * sp(t, b(1, 2), WOBBLE);
    const tchYaw = PI;
    return [
      hero, fa, fb, fc,
      seated("npc1", CAST.npc1, seat(0, 0)), seated("npc2", CAST.npc2, seat(0, 1)),
      seated("npc3", CAST.npc3, seat(4, 1)), seated("npc4", CAST.npc4, seat(1, 1)),
      { id: "teacher", look: CAST.teacher, pose: writing(t), p: [-0.4, 0.08, 3.85], yaw: tchYaw },
    ];
  }
  // ---------------- someone ruins it, bar 4
  if (inAct(t, ACT.ruin) || (t >= b(2, 0.5) && t < b(4))) {
    // Hero crouch-walks up the aisle toward the door, then freezes mid-step when the teacher turns.
    const walkEnd = b(4, 2);
    const tw = Math.min(t, walkEnd);
    const u = clamp01((tw - (b(4) - 0.4)) / (walkEnd - (b(4) - 0.4)));
    const hp: V3 = [-0.75 + 2.2 * u, 0, -1.2 + 1.9 * u];
    const frozen = t >= walkEnd;
    const hero: Actor = {
      id: "hero", look: CAST.hero, p: hp, yaw: PI - 0.85,
      pose: frozen ? { ...walkPose(tw * 9, 0.9, 1), headY: -0.6 * sp(t, walkEnd + 0.08, SNAP) } : walkPose(tw * 9, 0.9, 1),
      squash: frozen ? 1 + 0.12 * Math.exp(-(t - walkEnd) * 8) * Math.cos((t - walkEnd) * 30) : 1,
    };
    const fb = seated("friendB", CAST.friendB, seat(5, 0));
    // Talking: head bobs on the 8ths.
    fb.pose.headX = -0.12 * Math.abs(Math.sin((t - b(4, 1)) * PI / (BEAT / 2))) * (t > b(4, 1) && t < b(4, 2) ? 1 : 0);
    fb.pose.armRX = t > b(4, 1) && t < b(4, 2) ? 0.9 : 0.5;
    const turn = sp(t, b(4, 2), WOBBLE);
    const teacher: Actor = {
      id: "teacher", look: CAST.teacher, p: [0.3, 0.08, 3.85], yaw: PI - PI * turn,
      pose: t < b(4, 2) ? writing(t) : mixPose(writing(t), { ...REST, armLX: 0.4, armRX: 1.5, armRZ: 0.2, headX: 0.1 }, clamp01((t - b(4, 2)) / 0.15)),
      squash: 1 + 0.18 * Math.exp(-(t - b(4, 2)) * 9) * Math.sin(Math.max(0, t - b(4, 2)) * 26),
    };
    return [
      hero, fb, teacher,
      seated("friendA", CAST.friendA, seat(2, 1)), seated("friendC", CAST.friendC, seat(1, 0)),
      seated("npc1", CAST.npc1, seat(0, 0)), seated("npc2", CAST.npc2, seat(0, 1)),
      seated("npc3", CAST.npc3, seat(4, 1)), seated("npc4", CAST.npc4, seat(1, 1)),
    ];
  }
  // ---------------- corridor: excuse, trolley, paper ball
  if (inAct(t, ACT.excuse)) {
    const hero: Actor = { id: "hero", look: CAST.hero, p: [-0.9, 0, 0.2], yaw: -PI / 2 + 0.3, pose: { ...REST, armLX: 0.5 * sp(t, b(6, 1)), armRX: 0.9 * sp(t, b(6, 1)) + 0.3 * Math.sin(t * 14) * (t > b(6, 1) ? 1 : 0) } };
    // The proctor stands arms folded-ish, leaning in.
    const lean = sp(t, b(6, 0.25), WOBBLE);
    const proc: Actor = { id: "proctor", look: CAST.proctor, p: [0.35, 0, 0.1], yaw: PI / 2 - 0.2, pose: { ...REST, torsoX: -0.18 * lean, armLX: 1.1, armRX: 1.1, armLZ: 0.55, armRZ: -0.55 } };
    // At the snitch pick, a friend down the corridor freezes.
    return [hero, proc];
  }
  if (inAct(t, ACT.trolley)) {
    const d = t - b(7);
    // Trolley already moving at impact; friendB pushes it, the proctor flies back and lands flat.
    const fall = step(d, { stiffness: 260, damping: 13 });
    const proc: Actor = {
      id: "proctor", look: CAST.proctor, p: [0.9 + 1.4 * Math.min(1, d * 3.2), Math.max(0, 1.2 * Math.sin(Math.min(PI, d * 5))) * 0.6, 0.2],
      yaw: PI / 2, roll: -PI / 2 * Math.min(1.05, fall), pose: { ...REST, armLX: 2.6, armRX: 2.4, armLZ: -0.6, armRZ: 0.6, legL: -0.5, legR: 0.4 },
    };
    const tx = -0.35 + 1.6 * (1 - Math.exp(-d * 4));
    const pusher: Actor = { id: "friendB", look: CAST.friendB, p: [tx - 1.25, 0, 0.2], yaw: -PI / 2, pose: { ...walkPose(t * 14, 1, 0, true), armLX: 1.3, armRX: 1.3 } };
    return [proc, pusher];
  }
  if (inAct(t, ACT.paper)) {
    const hit = b(7, 2) + 0.3;
    const hero: Actor = { id: "hero", look: CAST.hero, p: [-1.6, 0, 0.1], yaw: -PI / 2, pose: { ...REST, armRX: 2.8 - 2.0 * sp(t, b(7, 2), SNAP), torsoX: -0.1 } };
    const bonk = sp(t, hit, WOBBLE);
    const teacher: Actor = { id: "teacher", look: CAST.teacher, p: [2.2, 0, 0.3], yaw: PI + 0.2 - 1.5 * bonk, pose: { ...REST, headX: t > hit ? 0.3 * Math.exp(-(t - hit) * 6) * Math.cos((t - hit) * 30) : 0 }, squash: t > hit ? 1 - 0.1 * Math.exp(-(t - hit) * 8) * Math.cos((t - hit) * 28) : 1 };
    return [hero, teacher];
  }
  // ---------------- test: hero seated from behind (backdrop for the paper)
  if (inAct(t, ACT.spray) || inAct(t, ACT.test)) {
    return [
      seated("hero", CAST.hero, seat(3, 0)), seated("friendA", CAST.friendA, seat(2, 1)),
      seated("npc4", CAST.npc4, seat(1, 1)), seated("friendC", CAST.friendC, seat(1, 0)),
      { id: "teacher", look: CAST.teacher, p: [0.4, 0.08, 3.4], yaw: 0, pose: { ...REST, armLX: 0.6 } },
    ];
  }
  // ---------------- panic: staff charge down the corridor at the camera
  if (inAct(t, ACT.panic)) {
    const d = t - b(9);
    const frozen = t >= b(9, 3.5);
    const tt = frozen ? b(9, 3.5) : t;
    const run = (id: string, look: Look, x: number, z0: number, speed: number, ph: number): Actor => ({
      id, look, p: [z0 - speed * (tt - b(9)), 0, x], yaw: PI / 2, pose: { ...walkPose(tt * 13 + ph, 1, 0, true), armLX: 0.9 * Math.sin(tt * 13 + ph) * 1.3, armRX: -0.9 * Math.sin(tt * 13 + ph) * 1.3 },
    });
    void d;
    return [
      run("guard", CAST.guard, -0.9, 8.8, 2.4, 0), run("proctor", CAST.proctor, 0.9, 9.4, 2.5, 1.3),
      run("teacher", CAST.teacher, 0.0, 10.4, 2.6, 2.1), run("guard2", { ...CAST.guard, skin: "#e0ac7e" }, -1.7, 11.6, 2.5, 0.7),
    ];
  }
  // ---------------- chase outside: the gang sprints right, staff behind
  if (inAct(t, ACT.chase)) {
    const d = t - b(10);
    const x0 = -14 + d * 7.6;
    const sprint = (id: string, look: Look, dx: number, z: number, ph: number, jumpAt?: number): Actor => {
      let y = 0;
      if (jumpAt !== undefined) {
        const j = t - jumpAt;
        if (j > 0 && j < 0.42) y = 1.1 * Math.sin((j / 0.42) * PI);
      }
      const pose = walkPose(t * 15 + ph, 1, 0, true);
      return { id, look, p: [x0 + dx, y, z], yaw: -PI / 2, pose: { ...pose, armLX: pose.armLX * 1.6, armRX: pose.armRX * 1.6 } };
    };
    return [
      sprint("hero", CAST.hero, 2.4, -8.7, 0, b(10, 2)), sprint("friendA", CAST.friendA, 1.2, -9.7, 1.1, b(10, 2.25)),
      sprint("friendB", CAST.friendB, 0.2, -8.3, 2.2, b(10, 2.5)), sprint("friendC", CAST.friendC, -0.8, -9.3, 0.6, b(10, 2.75)),
      sprint("guard", CAST.guard, -4.4, -8.9, 0.3), sprint("proctor", CAST.proctor, -5.6, -9.6, 1.7),
    ];
  }
  // ---------------- escape through the gate
  if (t >= b(12) && t < b(13, 2)) {
    const run = (id: string, look: Look, delay: number, x: number): Actor => {
      const d = t - b(12, 0.5) - delay;
      const z = -4 + d * 9;
      return { id, look, p: [x + (z > 4 ? (z - 4) * 0.9 : 0), 0, Math.min(z, 16)], yaw: z > 4 ? PI - 0.55 : PI, pose: walkPose(t * 15 + delay * 7, 1, 0, true) };
    };
    const guardTurn = sp(t, b(12, 3), WOBBLE);
    return [
      run("hero", CAST.hero, 0, -0.3), run("friendA", CAST.friendA, 0.18, 0.5), run("friendB", CAST.friendB, 0.34, -0.6), run("friendC", CAST.friendC, 0.5, 0.3),
      { id: "guard", look: CAST.guard, p: [4.1, 0, 1.2], yaw: 0.9 - 2.4 * guardTurn, chai: true, pose: { ...REST, armRX: 1.2 + 0.25 * Math.sin(t * 3), headX: 0.2 - 0.3 * guardTurn } },
    ];
  }
  // ---------------- logo: the hero drops onto the wall and waves (art/icon.png pose)
  if (t >= b(13, 2)) {
    const land = b(14);
    const fallU = clamp01((t - (land - 0.28)) / 0.28);
    const y = t < land ? 1.135 + 5 * (1 - fallU * fallU) : 1.135;
    const sq = t < land ? 1 + 0.2 * fallU : 1 - 0.3 * Math.exp(-(t - land) * 9) * Math.cos((t - land) * 26);
    const wave = t > land ? sp(t, land + 0.05, WOBBLE) : 0;
    const hop = t > b(15) ? Math.max(0, 0.35 * Math.sin(Math.min(PI, (t - b(15)) * PI / 0.35))) : 0;
    return [{
      id: "hero", look: CAST.hero, p: [0.25, y + hop, 0.25], yaw: 0.25, squash: sq,
      pose: { ...REST, armRX: 2.95 * wave, armRZ: 0.25 * wave + 0.12 * Math.sin((t - land) * 12) * wave, headX: 0.1 },
    }];
  }
  return [];
}

export { HIP_HEIGHT };
