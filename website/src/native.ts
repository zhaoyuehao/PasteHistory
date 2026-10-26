// Direct ports of IvoryTreeLayout, IvoryPaperStyle, TreeMotion and Motion.
// Reference: native main 0765399. Keep source references beside non-obvious math.
export const NATIVE = {
  pageSize: 8,
  width: 158,
  height: 74,
  selectedHeight: 112,
  imageHeight: 98,
  selectedImageHeight: 128,
  phoneWidth: 72,
  pin: 7,
  drops: [24, 33, 22, 37, 29, 21, 38, 26],
  tilts: [-4, 3, -2, 5, 2, -5, 3, -3],
  pageDuration: 0.28,
  outgoing: 0.14,
  incoming: 0.23,
  stagger: 0.006,
  fade: 0.15,
  openDuration: 0.24,
  followFrequency: 46,
  followDamping: 0.86,
  followBlend: (dt: number) => 1 - Math.pow(0.62, dt * 60),
};
export const PHONE_ID = "00000000-0000-4000-8000-000000000001";
export type Pose = {
  x: number;
  y: number;
  width: number;
  height: number;
  angle: number;
  inset: number;
};
export const clamp = (v: number, a: number, b: number) =>
  Math.max(a, Math.min(b, v));
export const dateLabel = (time: number) =>
  new Date(time).toLocaleString("zh-CN", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });

// SettlingTrack.sample: finite duration with velocity retained when interrupted.
export class Track {
  start = 0;
  end = 0;
  velocity = 0;
  duration = 0.24;
  symmetric = true;
  constructor(
    start: number,
    end = start,
    velocity = 0,
    duration = 0.24,
    symmetric = true,
  ) {
    Object.assign(this, { start, end, velocity, duration, symmetric });
  }
  sample(elapsed: number) {
    const t = clamp(elapsed / Math.max(0.001, this.duration), 0, 1),
      tail = 1 - t;
    return {
      value:
        this.start +
        (this.end - this.start) *
          (this.symmetric ? t * t * (3 - 2 * t) : 1 - tail ** 3 * (1 + 3 * t)) +
        this.velocity * this.duration * t * tail ** 3,
      velocity:
        ((this.end - this.start) *
          (this.symmetric ? 6 * t * tail : 12 * t * tail * tail)) /
          this.duration +
        this.velocity * tail * tail * (1 - 4 * t),
    };
  }
}
