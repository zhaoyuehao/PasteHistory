import { Track, NATIVE as N, clamp, type Pose } from "./native";
const keys = ["x", "y", "width", "height", "angle", "inset"] as const;
export class NativePreview {
  private pose: Pose = { x: 0, y: 0, width: 1, height: 1, angle: 0, inset: 7 };
  private source: Pose = { ...this.pose };
  private target: Pose = { ...this.pose };
  private tracks: Track[] = [];
  private phaseTrack = new Track(0);
  private phase = 0;
  private start = 0;
  private duration = 0.24;
  private frame = 0;
  private last = 0;
  private displayedElapsed = 0;
  private flightOpening = true;
  private firstFrame = false;
  private want = false;
  private identity: string | null = null;
  private base = { width: 340, height: 210 };
  private zoom = 1;
  private gestureZoom = 1;
  private vx = 0;
  private vy = 0;
  private zoomTimer: ReturnType<typeof setTimeout> | undefined;
  private bounceStarted = -1000;
  private bounceDirection = 1;
  private face: HTMLElement;
  private compact: HTMLElement;
  private reduced = matchMedia("(prefers-reduced-motion: reduce)");
  onClosed: () => void = () => {};
  onCollapse: () => void = () => {};
  constructor(private host: HTMLElement) {
    this.face = host.querySelector(".preview-face")!;
    this.compact = host.querySelector(".preview-compact")!;
    let down: { x: number; y: number } | null = null;
    host.addEventListener("pointerdown", (e) => {
      down =
        e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey
          ? { x: e.clientX, y: e.clientY }
          : null;
    });
    host.addEventListener("pointermove", (e) => {
      if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 5)
        down = null;
    });
    host.addEventListener("pointerup", (e) => {
      const click =
        down && Math.hypot(e.clientX - down.x, e.clientY - down.y) <= 5;
      down = null;
      if (
        click &&
        !getSelection()?.toString() &&
        !(e.target as Element).closest("button,a,input")
      )
        this.onCollapse();
    });
    host.addEventListener(
      "scroll",
      () => {
        down = null;
      },
      true,
    );
    host.addEventListener(
      "wheel",
      (e) => {
        down = null;
        if (!e.ctrlKey || !this.want) return;
        e.preventDefault();
        if (this.tracks.length) return;
        this.magnify(Math.exp(-e.deltaY * 0.01));
        clearTimeout(this.zoomTimer);
        this.zoomTimer = setTimeout(
          () => this.setZoom(clamp(this.zoom, 1, this.maximum())),
          150,
        );
      },
      { passive: false },
    );
    // Safari's native trackpad gesture events are confined to this preview.
    let lastScale = 1;
    host.addEventListener("gesturestart", ((e: Event) => {
      if (!this.want) return;
      e.preventDefault();
      lastScale = 1;
      this.gestureZoom = this.zoom;
      down = null;
    }) as EventListener);
    host.addEventListener("gesturechange", ((e: Event) => {
      if (!this.want) return;
      e.preventDefault();
      const scale = (e as Event & { scale: number }).scale;
      this.magnify(scale / lastScale);
      lastScale = scale;
    }) as EventListener);
    host.addEventListener("gestureend", ((e: Event) => {
      e.preventDefault();
      this.setZoom(clamp(this.zoom, 1, this.maximum()));
    }) as EventListener);
    let touchDistance = 0;
    host.addEventListener(
      "touchstart",
      (e) => {
        if (e.touches.length !== 2 || !this.want) return;
        down = null;
        this.gestureZoom = this.zoom;
        touchDistance = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY,
        );
      },
      { passive: true },
    );
    host.addEventListener(
      "touchmove",
      (e) => {
        if (e.touches.length !== 2 || !touchDistance || !this.want) return;
        e.preventDefault();
        down = null;
        const distance = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY,
        );
        this.magnify(distance / touchDistance);
        touchDistance = distance;
      },
      { passive: false },
    );
    host.addEventListener("touchend", () => {
      if (!touchDistance) return;
      touchDistance = 0;
      down = null;
      this.setZoom(clamp(this.zoom, 1, this.maximum()));
    });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        cancelAnimationFrame(this.frame);
        this.frame = 0;
      } else this.wake();
    });
  }
  get isVisible() {
    return !this.host.hidden;
  }
  dismissImmediately() {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.tracks = [];
    this.want = false;
    this.host.hidden = true;
    this.identity = null;
    this.phase = 0;
    this.onClosed();
  }
  bounce(direction: number) {
    if (
      !this.want ||
      this.reduced.matches ||
      performance.now() / 1000 - this.bounceStarted < 0.7
    )
      return;
    this.bounceDirection = direction;
    this.bounceStarted = performance.now() / 1000;
    this.wake();
  }
  private maximum() {
    return Math.min(
      2,
      Math.max(
        1,
        Math.min(
          (innerWidth - 24) / this.base.width,
          (innerHeight - 54) / this.base.height,
        ),
      ),
    );
  }
  zoomBy(factor: number) {
    if (this.want && !this.tracks.length)
      this.setZoom(clamp(this.zoom * factor, 1, this.maximum()));
  }
  private magnify(factor: number) {
    if (this.tracks.length) return;
    this.gestureZoom = clamp(
      this.gestureZoom * factor,
      0.5,
      this.maximum() * 1.5,
    );
    const bounded = clamp(this.gestureZoom, 1, this.maximum());
    this.zoom = bounded + (this.gestureZoom - bounded) * 0.12;
    this.target = this.readingPose();
    this.pose = { ...this.target };
    this.paint();
  }
  private setZoom(value: number) {
    if (!this.want || this.host.hidden) return;
    this.zoom = value;
    this.gestureZoom = value;
    this.target = this.readingPose();
    this.retarget(true, 0.15);
  }
  private readingPose(): Pose {
    const fit = Math.min(
      1,
      (innerWidth - 24) / (this.base.width * this.zoom),
      (innerHeight - 54) / (this.base.height * this.zoom),
    );
    const width = this.base.width * this.zoom * fit,
      height = this.base.height * this.zoom * fit,
      inset = 7 * this.zoom * fit;
    const x =
      clamp(this.source.x - width / 2, 12, innerWidth - width - 12) + width / 2;
    const y =
      clamp(this.source.y - inset, 42, innerHeight - height - 12) + inset;
    return { x, y, width, height, angle: 0, inset };
  }
  update(
    id: string | null,
    source: Pose | undefined,
    want: boolean,
    size: { width: number; height: number },
    snapshot: () => HTMLElement | undefined,
  ) {
    if (!want && this.host.hidden) return;
    if (source) this.source = source;
    if (!source && this.host.hidden) return;
    const opening = want && !this.want,
      identityChanged = id !== this.identity;
    if (want && this.host.hidden) {
      this.base = size;
      this.zoom = this.gestureZoom = 1;
      this.pose = { ...this.source };
      this.phase = 0;
      this.face.style.width = `${size.width}px`;
      this.face.style.height = `${size.height}px`;
      this.host.hidden = false;
    }
    if ((want && (opening || identityChanged)) || (!want && this.want)) {
      const clone = snapshot();
      if (clone) {
        clone.removeAttribute("id");
        clone.inert = true;
        clone.removeAttribute("aria-hidden");
        const width = parseFloat(clone.style.width),
          height = parseFloat(clone.style.height);
        clone.style.cssText = `position:absolute;left:0;top:0;width:${width}px;height:${height}px;transform:scale(${this.source.width / width});transform-origin:0 0;opacity:1`;
        this.compact.replaceChildren(clone);
      }
    }
    const changed = this.want !== want || identityChanged;
    this.want = want;
    this.identity = id;
    this.host.inert = !want;
    const destination = want ? this.readingPose() : { ...this.source };
    const shifted = keys.some(
      (k) => Math.abs(destination[k] - this.target[k]) > 0.05,
    );
    this.target = destination;
    if (changed || (shifted && this.tracks.length)) this.retarget(want);
    else if (!this.tracks.length && want) this.wake();
  }
  private retarget(opening: boolean, duration = N.openDuration) {
    const now = performance.now() / 1000,
      elapsed = now - this.start,
      interrupted = this.tracks.length > 0;
    const speeds = interrupted
      ? this.tracks.map((t) => t.sample(this.displayedElapsed).velocity)
      : [this.vx, this.vy, 0, 0, 0, 0];
    const remaining = !interrupted
      ? duration
      : this.flightOpening === opening
        ? Math.min(duration, Math.max(0.08, this.duration - elapsed))
        : Math.max(
            0.08,
            duration * Math.sqrt(Math.abs((opening ? 1 : 0) - this.phase)),
          );
    this.duration = remaining;
    this.tracks = keys.map(
      (k, i) =>
        new Track(this.pose[k], this.target[k], speeds[i], this.duration),
    );
    this.phaseTrack = new Track(
      this.phase,
      opening ? 1 : 0,
      interrupted ? this.phaseTrack.sample(this.displayedElapsed).velocity : 0,
      this.duration,
    );
    this.flightOpening = opening;
    this.firstFrame = !interrupted;
    this.displayedElapsed = 0;
    if (this.reduced.matches && opening) this.pose = { ...this.target };
    this.start = now;
    this.last = now;
    this.paint();
    this.wake();
  }
  private wake() {
    if (!this.frame && !document.hidden && !this.host.hidden) {
      this.last = performance.now() / 1000;
      this.frame = requestAnimationFrame((t) => this.tick(t / 1000));
    }
  }
  private tick(now: number) {
    this.frame = 0;
    const dt = Math.min(1 / 30, Math.max(0, now - this.last));
    this.last = now;
    let active = false;
    if (this.tracks.length) {
      if (this.firstFrame) {
        this.start = now;
        this.firstFrame = false;
      }
      const elapsed = now - this.start;
      this.displayedElapsed = elapsed;
      if (!this.reduced.matches)
        keys.forEach((k, i) => {
          this.pose[k] = this.tracks[i].sample(elapsed).value;
        });
      this.phase = this.phaseTrack.sample(elapsed).value;
      active = elapsed < this.duration;
      if (!active) {
        this.pose = { ...this.target };
        this.phase = this.want ? 1 : 0;
        this.tracks = [];
        if (!this.want) {
          this.host.hidden = true;
          this.identity = null;
          this.onClosed();
          return;
        }
      }
    } else if (this.want) {
      // PaperPreviewFollow's analytic damped oscillator; no accumulated eases.
      const omega = N.followFrequency,
        damping = N.followDamping,
        decay = Math.exp(-damping * omega * dt),
        wd = omega * Math.sqrt(1 - damping * damping),
        cos = Math.cos(wd * dt),
        sin = Math.sin(wd * dt);
      for (const key of ["x", "y"] as const) {
        const speed = key === "x" ? this.vx : this.vy,
          offset = this.pose[key] - this.target[key];
        this.pose[key] = this.reduced.matches
          ? this.target[key]
          : this.target[key] +
            decay *
              (offset * cos + ((speed + damping * omega * offset) / wd) * sin);
        const v =
          decay *
          (speed * cos -
            ((omega * omega * offset + damping * omega * speed) / wd) * sin);
        if (key === "x") this.vx = v;
        else this.vy = v;
      }
      active =
        Math.hypot(this.pose.x - this.target.x, this.pose.y - this.target.y) >
          0.5 || Math.hypot(this.vx, this.vy) > 4;
      if (!active) {
        this.pose = { ...this.target };
        this.vx = this.vy = 0;
      }
    }
    const bounceTime = now - this.bounceStarted;
    const content = this.face.querySelector<HTMLElement>("#preview-content")!;
    if (bounceTime < 0.7 && !this.reduced.matches) {
      const omega = (2 * Math.PI) / 0.32,
        damping = 0.55,
        wd = omega * Math.sqrt(1 - damping * damping);
      const offset =
        8 *
        this.bounceDirection *
        Math.exp(-damping * omega * bounceTime) *
        (Math.cos(wd * bounceTime) +
          ((damping * omega) / wd) * Math.sin(wd * bounceTime));
      content.style.transform = `translateY(${offset}px)`;
      active = true;
    } else content.style.removeProperty("transform");
    this.paint();
    if (active) this.frame = requestAnimationFrame((t) => this.tick(t / 1000));
  }
  private paint() {
    const p = this.pose;
    this.host.style.setProperty("--pin-inset", `${p.inset}px`);
    this.host.style.setProperty("--hole-radius", `${(1.7 * p.inset) / 7}px`);
    Object.assign(this.host.style, {
      width: `${p.width}px`,
      height: `${p.height}px`,
      transform: `translate(${p.x - p.width / 2}px,${p.y - p.inset}px) rotate(${p.angle}deg)`,
      transformOrigin: `50% ${p.inset}px`,
      opacity: String(this.reduced.matches ? clamp(this.phase, 0, 1) : 1),
    });
    const scale = Math.min(
      p.width / this.base.width,
      p.height / this.base.height,
    );
    const relative = Math.max(
      p.width / Math.max(1, this.source.width),
      p.height / Math.max(1, this.source.height),
    );
    const t = clamp((relative - 1) / 0.4, 0, 1),
      blend = t * t * (3 - 2 * t);
    this.face.style.transform = `translateX(${(p.width - this.base.width * scale) / 2}px) scale(${scale})`;
    this.face.style.opacity = String(blend);
    this.compact.style.opacity = String(1 - blend);
  }
}
