import { Track, clamp } from "./native";
// TreeEntrance.swift: one trajectory moves the sculpture, papers and search.
export class TreeEntrance {
  private y = new Track(0);
  private alpha = new Track(1);
  private position = 0;
  private opacity = 1;
  private start = 0;
  private frame = 0;
  private shown = true;
  private duration = 0.2;
  private reduced = matchMedia("(prefers-reduced-motion: reduce)");
  onLayout: () => void = () => {};
  constructor(private host: HTMLElement) {
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        cancelAnimationFrame(this.frame);
        this.frame = 0;
      } else if (this.opacity !== (this.shown ? 1 : 0)) this.wake();
    });
  }
  show(value: boolean) {
    if (this.shown === value) return;
    const now = performance.now() / 1000,
      elapsed = now - this.start;
    const velocity = this.frame ? this.y.sample(elapsed).velocity : 0;
    const alphaVelocity = this.frame ? this.alpha.sample(elapsed).velocity : 0;
    if (value && this.opacity === 0)
      this.position = this.reduced.matches ? 0 : 12;
    this.shown = value;
    this.duration = value ? 0.2 : 0.15;
    this.y = new Track(this.position, 0, velocity, this.duration, false);
    this.alpha = new Track(
      this.opacity,
      value ? 1 : 0,
      alphaVelocity,
      value ? 0.09 : 0.15,
      false,
    );
    this.start = now;
    this.wake();
  }
  private wake() {
    if (!this.frame && !document.hidden)
      this.frame = requestAnimationFrame((now) => this.tick(now / 1000));
  }
  private tick(now: number) {
    this.frame = 0;
    const elapsed = now - this.start;
    this.position = this.y.sample(elapsed).value;
    this.opacity = clamp(this.alpha.sample(elapsed).value, 0, 1);
    this.host.style.translate = `0 ${this.reduced.matches ? 0 : this.position}px`;
    this.host.style.opacity = String(this.opacity);
    this.onLayout();
    if (elapsed < this.duration) this.wake();
  }
}
