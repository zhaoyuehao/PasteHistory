// DriftCourse and BoatTraffic, in browser coordinates (+y points down).
import { displacement } from "./waves.js";
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
function clear(a, b, safe) {
  const steps = Math.max(1, Math.ceil(dist(a, b) / 8));
  for (let i = 0; i <= steps; i++) {
    const f = i / steps;
    if (!safe(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)) return false;
  }
  return true;
}
function goal(b, start, ux, uy, map) {
  const { points, w, h, safe } = map,
    diag = Math.hypot(w, h);
  const region = (p) =>
    Math.min(3, Math.floor((4 * p.x) / w)) +
    4 * Math.min(2, Math.floor((3 * p.y) / h));
  const choices = points
    .map((p) => {
      const d = Math.max(0.001, dist(p, start)),
        bearing = ((p.x - start.x) * ux + (p.y - start.y) * uy) / d;
      const score =
        -2 * b.visits[region(p)] +
        Math.min(0.7, d / diag) +
        0.8 * bearing +
        Math.random() -
        Math.max(0, -0.62 - bearing) * 8 -
        (d < diag * 0.26 ? 3 : 0);
      return { p, score };
    })
    .sort((a, b) => b.score - a.score);
  const p = choices.find((c) => clear(start, c.p, safe))?.p ?? start;
  b.visits[region(p)]++;
  return p;
}
function leg(b, map) {
  b.path = [];
  b.next = 0;
  const d = b.destination,
    len = dist(b, d);
  if (len < 1) {
    b.destination = goal(b, b, 0, 0, map);
    b.path = [b.destination];
    return;
  }
  const x = (d.x - b.x) / len,
    y = (d.y - b.y) / len,
    to = goal(b, d, x, y, map),
    after = dist(to, d);
  for (let r = Math.min(115, 0.28 * Math.min(len, after)); r > 2; r /= 2) {
    const a = { x: d.x - x * r, y: d.y - y * r },
      c = {
        x: d.x + ((to.x - d.x) * r) / after,
        y: d.y + ((to.y - d.y) * r) / after,
      };
    const curve = Array.from({ length: 33 }, (_, i) => {
      const t = i / 32,
        u = 1 - t;
      return {
        x: u * u * a.x + 2 * u * t * d.x + t * t * c.x,
        y: u * u * a.y + 2 * u * t * d.y + t * t * c.y,
      };
    });
    if (
      clear(b, a, map.safe) &&
      curve.every((p, i) => !i || clear(curve[i - 1], p, map.safe))
    ) {
      b.path = curve;
      break;
    }
  }
  if (!b.path.length) b.path = [d];
  b.destination = to;
}
function preferred(b, map, now) {
  b.visits ??= new Uint16Array(12);
  if (!b.path) {
    b.destination = goal(b, b, 0, 0, map);
    leg(b, map);
  }
  while (b.next < b.path.length && dist(b, b.path[b.next]) < 6) b.next++;
  if (b.next === b.path.length) leg(b, map);
  const p = b.path[b.next],
    len = p ? dist(b, p) : 0;
  const speed =
    b.cruise *
    Math.min(
      3,
      1 +
        b.clicks.reduce(
          (s, t) => s + 0.35 * Math.max(0, 1 - (now - t) / 604800000) ** 2,
          0,
        ),
    );
  return len > 0.01
    ? [((p.x - b.x) * speed) / len, ((p.y - b.y) * speed) / len]
    : [0, 0];
}
export function advance(boats, map, dt, t, strength, held) {
  const now = Date.now(),
    scale = map.w < 600 ? 0.78 : 1;
  const states = boats.map((b) => {
    const fixed = b.hold || b === held;
    const [px, py] = fixed ? [0, 0] : preferred(b, map, now);
    const [sx, sy] = displacement(b.x, map.h - b.y, t, strength);
    return { b, px, py, sx, sy: -sy, ax: 0, ay: 0, fixed };
  });
  function pairs(f) {
    for (let i = 0; i < states.length; i++)
      for (let j = i + 1; j < states.length; j++) f(states[i], states[j]);
  }
  pairs((a, b) => {
    const dx = a.b.x + a.sx - b.b.x - b.sx,
      dy = a.b.y + a.sy - b.b.y - b.sy;
    const vx = a.px - b.px,
      vy = a.py - b.py,
      v = Math.hypot(vx, vy);
    const time = -(dx * vx + dy * vy) / Math.max(0.001, v * v);
    if (time <= 0 || time >= 12) return;
    const miss = Math.hypot(dx + time * vx, dy + time * vy);
    if (miss >= 96 * scale) return;
    let nx = -vy / v,
      ny = vx / v;
    if (dx * nx + dy * ny < -2) {
      nx = -nx;
      ny = -ny;
    }
    const strength = 2.4 * (1 - miss / (96 * scale)) * (1 - time / 12),
      sa = strength * Math.hypot(a.px, a.py),
      sb = strength * Math.hypot(b.px, b.py);
    a.ax += nx * sa;
    a.ay += ny * sa;
    b.ax -= nx * sb;
    b.ay -= ny * sb;
  });
  for (const s of states) {
    const b = s.b;
    if (s.fixed) {
      b.vx = b.vy = 0;
      continue;
    }
    const tx = s.px + s.ax,
      ty = s.py + s.ay,
      limit = Math.min(
        1,
        Math.hypot(s.px, s.py) / Math.max(0.001, Math.hypot(tx, ty)),
      );
    const f = 1 - Math.exp(-2 * dt),
      vx = b.vx || 0,
      vy = b.vy || 0;
    const choices = [
      [vx + (tx * limit - vx) * f, vy + (ty * limit - vy) * f],
      [s.px, s.py],
    ];
    b.vx = b.vy = 0;
    for (const [x, y] of choices) {
      const p = { x: b.x + x * dt, y: b.y + y * dt };
      if (!clear(b, p, map.safe)) continue;
      b.x = p.x;
      b.y = p.y;
      b.vx = x;
      b.vy = y;
      break;
    }
    if (Math.hypot(b.vx, b.vy) > 0.1) b.heading = Math.atan2(b.vy, b.vx);
    else if (b.path?.[b.next] && !clear(b, b.path[b.next], map.safe))
      b.path = null;
  }
  // Three overlapping discs follow each projected keel. Labels never enter contacts.
  for (let pass = 0; pass < 12; pass++) {
    let changed = false;
    pairs((a, b) => {
      const dx = a.b.x + a.sx - b.b.x - b.sx,
        dy = a.b.y + a.sy - b.b.y - b.sy;
      if (Math.hypot(dx, dy) >= 104 * scale) return;
      const aa = a.b.angle ?? -a.b.heading,
        ba = b.b.angle ?? -b.b.heading;
      const contacts = [],
        limit = 46 * scale;
      let min = Infinity,
        nx = 0,
        ny = 0;
      for (const i of [-26, 1, 28])
        for (const j of [-26, 1, 28]) {
          const x = dx + scale * (i * Math.cos(aa) - j * Math.cos(ba)),
            y = dy - 0.79 * scale * (i * Math.sin(aa) - j * Math.sin(ba)),
            d = Math.hypot(x, y);
          if (d >= limit) continue;
          contacts.push([x, y]);
          if (d < min) {
            min = d;
            nx = d > 0.001 ? x / d : Math.sin(aa);
            ny = d > 0.001 ? y / d : Math.cos(aa);
          }
        }
      if (!contacts.length) return;
      if (nx * dx + ny * dy < 0) {
        nx = -nx;
        ny = -ny;
      }
      const depth =
        Math.max(
          ...contacts.map(([x, y]) => {
            const along = x * nx + y * ny;
            return (
              Math.sqrt(
                Math.max(0, limit * limit - x * x - y * y + along * along),
              ) - along
            );
          }),
        ) + 0.01;
      function can(s, sign, f) {
        return (
          !s.fixed &&
          map.safe(s.b.x + sign * f * depth * nx, s.b.y + sign * f * depth * ny)
        );
      }
      const left = can(a, 1, 0.5),
        right = can(b, -1, 0.5);
      for (const [s, sign, free, other] of [
        [a, 1, left, right],
        [b, -1, right, left],
      ]) {
        if (!free) continue;
        const f = !other && can(s, sign, 1) ? 1 : 0.5;
        s.b.x += sign * nx * depth * f;
        s.b.y += sign * ny * depth * f;
        changed = true;
        const into = Math.min(0, sign * (s.b.vx * nx + s.b.vy * ny));
        s.b.vx -= sign * into * nx;
        s.b.vy -= sign * into * ny;
      }
    });
    if (!changed) break;
  }
}
