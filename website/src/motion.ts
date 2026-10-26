// One continuous state per animated object: reversing changes the target, never the position or velocity.
export class Spring {
  value: number;
  velocity = 0;
  target: number;
  constructor(value: number) {
    this.value = value;
    this.target = value;
  }
  step(dt: number, fast = false) {
    const stiffness = fast ? 420 : 260,
      damping = fast ? 38 : 30;
    let t = Math.min(dt, 0.05);
    while (t > 0) {
      const h = Math.min(t, 1 / 120);
      this.velocity +=
        ((this.target - this.value) * stiffness - this.velocity * damping) * h;
      this.value += this.velocity * h;
      t -= h;
    }
    if (
      Math.abs(this.target - this.value) < 0.001 &&
      Math.abs(this.velocity) < 0.005
    ) {
      this.value = this.target;
      this.velocity = 0;
    }
    return this.value;
  }
  get settled() {
    return this.value === this.target && this.velocity === 0;
  }
}
