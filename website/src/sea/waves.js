// OceanWaves.swift: eight travelling bands, three of which carry the hulls.
const amplitudes = [4.1, 2.65, 1.6, 0.9, 0.57, 0.35, 0.2, 0.1];
const wind = -1.32 + Math.random() * 0.34;
const bands = [248, 168, 106, 63, 38, 23, 14, 9].map((length, i) => {
  const angle =
    wind + ([1, 4, 6].includes(i) ? 0.95 : 0) + (Math.random() - 0.5) * 0.58;
  const k = (2 * Math.PI) / (length * (0.91 + Math.random() * 0.18));
  return {
    x: Math.cos(angle),
    y: Math.sin(angle),
    k,
    a: amplitudes[i],
    omega: Math.sqrt(48 * k),
    seed: Math.random() * 2 * Math.PI,
  };
});
export const parameters = new Float32Array(64);
export function updateBands(time, strength) {
  bands.forEach(({ x, y, k, a, omega, seed }, i) =>
    parameters.set(
      [
        x,
        y,
        k,
        a * strength,
        (seed - time * omega) % (2 * Math.PI),
        (seed + time * omega * 0.21) % (2 * Math.PI),
        (seed - time * omega * 0.13) % (2 * Math.PI),
        seed,
      ],
      i * 8,
    ),
  );
}
export function displacement(x, y, t, strength) {
  let dx = 0,
    dy = 0;
  for (let i = 0; i < 3; i++) {
    const b = bands[i],
      along = (b.x * x + b.y * y) * b.k,
      side = (-b.y * x + b.x * y) * b.k;
    const group =
      0.66 +
      0.34 * Math.sin(along * 0.19 + side * 0.16 + b.seed - t * b.omega * 0.13);
    const phase =
      along +
      b.seed -
      t * b.omega +
      0.92 * Math.sin(side * 0.43 + b.seed + t * b.omega * 0.21) +
      0.38 * Math.sin(side * 0.81 + along * 0.09 + b.seed);
    const offset = b.a * group * Math.cos(phase) * strength;
    dx += b.x * offset;
    dy += b.y * offset;
  }
  return [dx, dy];
}
export function modelPose(b, height, t, dt, strength) {
  const y = height - b.y,
    vx = b.vx || 0,
    vy = -(b.vy || 0);
  const [dx, dy] = displacement(b.x, y, t, strength);
  const [ax, ay] = displacement(
    b.x + 0.8 * vx,
    y + 0.8 * vy,
    t + 0.8,
    strength,
  );
  const cx = (ax - dx) / 0.8,
    cy = (ay - dy) / 0.8,
    speed = Math.max(0.5, Math.hypot(vx, vy));
  const cross = (vx * cy - vy * cx) / speed,
    along = (vx * cx + vy * cy) / speed;
  const target =
    -b.heading + 0.42 * Math.atan2(cross, Math.max(3.5, speed + along));
  b.angle ??= target;
  b.turnRate ??= 0;
  for (let left = dt; left > 0; left -= 1 / 60) {
    const step = Math.min(left, 1 / 60),
      err = Math.atan2(Math.sin(target - b.angle), Math.cos(target - b.angle));
    const acc = Math.max(-2.4, Math.min(2.4, 16 * err - 8 * b.turnRate));
    b.turnRate = Math.max(-0.9, Math.min(0.9, b.turnRate + acc * step));
    b.angle += b.turnRate * step;
  }
  b.pose = [
    b.x + dx,
    y + dy,
    b.angle,
    0.07 * Math.sin(t * 0.9 + b.phase) + 0.02 * cross,
  ];
}
