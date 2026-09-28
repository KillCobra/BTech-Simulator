// A tiny twin of CSS 3D transforms, so 2D overlays (markers, routes, labels) can be pinned to points on
// CSS-3D cards and boards and stay crisp. Ops are listed in CSS order (left to right) and applied right to left.
export type Op = ["t", number, number, number] | ["rx", number] | ["ry", number] | ["rz", number] | ["s", number];

const rad = (d: number) => (d * Math.PI) / 180;

export const cssOf = (ops: Op[]) =>
  ops
    .map((o) => {
      if (o[0] === "t") return `translate3d(${o[1]}px, ${o[2]}px, ${o[3]}px)`;
      if (o[0] === "rx") return `rotateX(${o[1]}deg)`;
      if (o[0] === "ry") return `rotateY(${o[1]}deg)`;
      if (o[0] === "rz") return `rotateZ(${o[1]}deg)`;
      return `scale3d(${o[1]}, ${o[1]}, ${o[1]})`;
    })
    .join(" ");

/** A point in the element's local space (relative to its centre, the transform-origin) after the ops. */
export function apply(ops: Op[], p: [number, number, number]): [number, number, number] {
  let [x, y, z] = p;
  for (let i = ops.length - 1; i >= 0; i--) {
    const o = ops[i];
    if (o[0] === "t") { x += o[1]; y += o[2]; z += o[3]; }
    else if (o[0] === "s") { x *= o[1]; y *= o[1]; z *= o[1]; }
    else {
      const c = Math.cos(rad(o[1])), s = Math.sin(rad(o[1]));
      if (o[0] === "rx") [y, z] = [y * c - z * s, y * s + z * c];
      else if (o[0] === "ry") [x, z] = [x * c + z * s, -x * s + z * c];
      else [x, y] = [x * c - y * s, x * s + y * c];
    }
  }
  return [x, y, z];
}

/** Screen position of a local point: element centred at `centre`, parent perspective P with origin `po`. */
export function project(ops: Op[], centre: [number, number], P: number, po: [number, number], p: [number, number, number]) {
  const [x, y, z] = apply(ops, p);
  const k = P / (P - z);
  return { x: po[0] + (centre[0] + x - po[0]) * k, y: po[1] + (centre[1] + y - po[1]) * k, k };
}
