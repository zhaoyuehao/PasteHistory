import { t, locale } from "./i18n";
import { PerspectiveCamera, Vector3 } from "three";
import reference from "../public/native-tree.json";
import { NATIVE as N, PHONE_ID, clamp, dateLabel, type Pose } from "./native";
import type { Clip } from "./store";
export type Anchor = { x: number; y: number };
type Card = {
  el: HTMLButtonElement;
  cord: SVGPathElement;
  clip: Clip;
  slot: number;
  x: number;
  y: number;
  width: number;
  height: number;
  tilt: number;
  fold: number;
  opacity: number;
};
export class TreeStage {
  private camera = new PerspectiveCamera(38, 1, 0.1, 100);
  private image = document.createElement("img");
  private cords = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  private ring = document.createElement("div");
  private cards = new Map<string, Card>();
  private outgoing: {
    el: HTMLElement;
    x: number;
    y: number;
    tilt: number;
    fold: number;
    opacity: number;
  }[] = [];
  private selected: string | null = null;
  private hiddenPaper: string | null = null;
  private visible = true;
  private width = 880;
  private height = 920;
  private frame = 0;
  private last = 0;
  private turnStart = -1000;
  private direction = 1;
  private selectionFade = 1;
  private startIndex = 0;
  private signature = "";
  private ringPose: Pose | null = null;
  private reduced = matchMedia("(prefers-reduced-motion: reduce)");
  onSelect: (id: string) => void = () => {};
  onFocus: () => void = () => {};
  onDrag: (id: string) => void = () => {};
  onDragEnd: () => void = () => {};
  onLayout: () => void = () => {};
  constructor(private host: HTMLElement) {
    this.image.src = `${import.meta.env.BASE_URL}tree-native.png`;
    this.image.alt = t("原生 SceneKit 许愿树与五只小鸟");
    this.image.className = "native-sculpture";
    this.image.onerror = () => {
      this.image.src = `${import.meta.env.BASE_URL}tree-fallback.png`;
      this.image.onerror = null;
    };
    this.cords.classList.add("native-cords");
    this.cords.setAttribute("aria-hidden", "true");
    this.ring.className = "selection-ring";
    this.ring.setAttribute("aria-hidden", "true");
    host.append(this.image, this.cords, this.ring);
    new ResizeObserver(() => this.resize()).observe(host);
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        cancelAnimationFrame(this.frame);
        this.frame = 0;
      } else this.wake();
    });
    this.reduced.addEventListener("change", () => this.wake());
    this.resize();
  }
  private resize() {
    this.width = this.host.clientWidth;
    this.height = this.host.clientHeight;
    if (!this.width || !this.height) return;
    this.camera.aspect = this.width / this.height;
    this.camera.position.set(
      0,
      4.15,
      Math.max(
        5.25 / Math.tan((19 * Math.PI) / 180),
        4.1 / (Math.tan((19 * Math.PI) / 180) * this.camera.aspect),
      ),
    );
    this.camera.updateProjectionMatrix();
    this.camera.updateMatrixWorld();
    // SceneKit and its projected anchors share the same vertical FOV and distance.
    const scale =
      ((this.height / 920) * reference.cameraZ) / this.camera.position.z;
    this.image.style.width = `${880 * scale}px`;
    this.image.style.height = `${920 * scale}px`;
    this.image.style.left = `${(this.width - 880 * scale) / 2}px`;
    this.image.style.top = `${(this.height - 920 * scale) / 2}px`;
    this.cords.setAttribute("viewBox", `0 0 ${this.width} ${this.height}`);
    const root = this.project(reference.root);
    this.host.parentElement!.style.setProperty("--root-x", `${root.x}px`);
    this.host.parentElement!.style.setProperty(
      "--root-y",
      `${Math.min(this.height - 92, root.y + 18)}px`,
    );
    this.wake();
  }
  private project(xyz: number[]): Anchor {
    const p = new Vector3(...(xyz as [number, number, number])).project(
      this.camera,
    );
    return {
      x: ((p.x + 1) * this.width) / 2,
      y: ((1 - p.y) * this.height) / 2,
    };
  }
  anchor(slot: number) {
    return this.project(reference.anchors[slot]);
  }
  rect(id: string) {
    return this.cards.get(id)?.el.getBoundingClientRect();
  }
  pose(id: string): Pose | undefined {
    const c = this.cards.get(id);
    if (!c) return;
    const r = this.host.getBoundingClientRect();
    const scale = r.width / this.width;
    return {
      x: r.left + (c.x + c.width / 2) * scale,
      y: r.top + (c.y + N.pin) * scale,
      width: c.width * c.fold * scale,
      height: c.height * scale,
      angle: c.tilt,
      inset: N.pin * scale,
    };
  }
  compact(id: string) {
    const c = this.cards.get(id);
    return c?.el.cloneNode(true) as HTMLElement | undefined;
  }
  conceal(id: string | null) {
    if (this.hiddenPaper === id) return;
    this.hiddenPaper = id;
    this.wake();
  }
  render(
    entries: Clip[],
    selected: string | null,
    preview: boolean,
    visible: boolean,
    startIndex = 0,
  ) {
    if (this.selected !== selected && this.reduced.matches)
      this.selectionFade = 0;
    this.image.alt = t("原生 SceneKit 许愿树与五只小鸟");
    this.selected = selected;
    this.visible = visible;
    if (!preview) this.hiddenPaper = null;
    else this.hiddenPaper = selected;
    this.host.classList.toggle("tree-hidden", !visible);
    this.host.inert = !visible;
    const phone: Clip = {
      id: PHONE_ID,
      kind: "text",
      text: t("手机同步"),
      source: "",
      created: 0,
      pinned: false,
    };
    const all = [...entries, phone];
    const signature = all.map((c) => `${c.id}:${c.pinned}:${c.text}`).join("|");
    if (signature !== this.signature) {
      const oldFirst = this.startIndex;
      this.startIndex = startIndex;
      this.direction = startIndex >= oldFirst ? 1 : -1;
      // Match visuals().suffix(16): retain the presented incoming AND outgoing
      // papers when a new page interrupts the current turn.
      const previous = this.outgoing;
      const snapshots: {
        el: HTMLElement;
        x: number;
        y: number;
        tilt: number;
        fold: number;
        opacity: number;
      }[] = [];
      if (this.signature) {
        const candidates = [
          ...previous,
          ...[...this.cards.values()].filter((c) => c.clip.id !== PHONE_ID),
        ];
        for (const c of candidates.slice(-16)) {
          const opacity = Number(c.el.style.opacity);
          if (opacity <= 0.01) continue;
          const matrix = new DOMMatrixReadOnly(c.el.style.transform);
          const fold = Math.hypot(matrix.a, matrix.b);
          const tilt = (Math.atan2(matrix.b, matrix.a) * 180) / Math.PI;
          const el = c.el.cloneNode(true) as HTMLElement;
          el.removeAttribute("id");
          el.inert = false;
          (el as HTMLButtonElement).disabled = true;
          el.tabIndex = -1;
          el.setAttribute("aria-hidden", "true");
          el.classList.add("departing-paper");
          this.host.append(el);
          const x = c.x + matrix.e;
          el.style.left = `${x}px`;
          snapshots.push({ el, x, y: c.y, tilt, fold, opacity });
        }
        this.turnStart = performance.now() / 1000;
      }
      previous.forEach((c) => c.el.remove());
      this.outgoing = snapshots;
      this.signature = signature;
      for (const [id, c] of this.cards)
        if (!all.some((e) => e.id === id)) {
          c.el.remove();
          c.cord.remove();
          this.cards.delete(id);
        }
      all.forEach((clip, index) => {
        let c = this.cards.get(clip.id);
        if (!c) {
          const el = document.createElement("button");
          el.className = "paper";
          el.type = "button";
          el.dataset.clipId = clip.id;
          const cord = document.createElementNS(
            "http://www.w3.org/2000/svg",
            "path",
          );
          this.cords.append(cord);
          c = {
            el,
            cord,
            clip,
            slot: index,
            x: 0,
            y: 0,
            width: 158,
            height:
              clip.id === PHONE_ID
                ? 72 * 1.61803398875
                : clip.kind === "image"
                  ? clip.id === selected
                    ? 128
                    : 98
                  : clip.id === selected
                    ? 112
                    : 74,
            tilt: 0,
            fold: 1,
            opacity: 1,
          };
          this.cards.set(clip.id, c);
          this.host.append(el);
          let dragged = false,
            down: { x: number; y: number } | null = null;
          el.addEventListener("pointerdown", (e) => {
            if (e.button !== 0) return;
            this.onFocus();
            down = { x: e.clientX, y: e.clientY };
            dragged = false;
          });
          el.addEventListener("pointermove", (e) => {
            if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 5)
              dragged = true;
          });
          el.addEventListener("click", () => {
            if (
              !dragged &&
              performance.now() / 1000 - this.turnStart >= N.outgoing
            )
              this.onSelect(clip.id);
          });
          el.addEventListener("dragstart", (e) => {
            if (clip.id === PHONE_ID) {
              e.preventDefault();
              return;
            }
            dragged = true;
            e.dataTransfer?.setData("application/x-pastehistory", clip.id);
            e.dataTransfer?.setData(
              "text/plain",
              this.cards.get(clip.id)?.clip.text ?? clip.text,
            );
            if (e.dataTransfer) e.dataTransfer.effectAllowed = "copy";
            this.onDrag(clip.id);
          });
          el.addEventListener("dragend", () => {
            down = null;
            this.onDragEnd();
          });
        }
        c.clip = clip;
        c.el.lang = clip.lang ?? locale;
        c.slot = clip.id === PHONE_ID ? 8 : index;
        c.el.draggable = clip.id !== PHONE_ID;
        c.el.classList.toggle("phone-paper", clip.id === PHONE_ID);
        c.el.classList.toggle("image-paper", !!clip.image);
        c.el.setAttribute(
          "aria-label",
          clip.id === PHONE_ID ? t("手机同步") : `${clip.source}：${clip.text}`,
        );
        c.el.replaceChildren();
        if (clip.id === PHONE_ID) {
          const glyph = document.createElement("span");
          glyph.className = "phone-glyph";
          glyph.textContent = "▦";
          const label = document.createElement("span");
          label.className = "phone-label";
          label.textContent = t("手机同步");
          c.el.append(glyph, label);
        } else {
          const meta = document.createElement("span");
          meta.className = "paper-meta";
          meta.textContent = `${String(startIndex + index + 1).padStart(2, "0")}${clip.pinned ? " · ↟ " : " · "}${clip.source || "—"}`;
          const body = document.createElement("span");
          body.className = "paper-body";
          if (clip.image) {
            const img = document.createElement("img");
            img.src = clip.image;
            img.alt = clip.text;
            body.append(img);
          } else {
            body.classList.add("paper-text");
            body.textContent = clip.text.slice(0, 500);
          }
          const date = document.createElement("span");
          date.className = "paper-date";
          date.textContent = dateLabel(clip.created);
          c.el.append(meta, body, date);
        }
      });
    }
    this.wake();
  }
  wake() {
    if (!this.frame && !document.hidden) {
      this.last = performance.now();
      this.frame = requestAnimationFrame((t) => this.tick(t));
    }
  }
  private tick(now: number) {
    this.frame = 0;
    const dt = clamp((now - this.last) / 1000, 1 / 240, 1 / 30);
    this.last = now;
    const elapsed = now / 1000 - this.turnStart,
      blend = N.followBlend(dt),
      reduced = this.reduced.matches;
    this.selectionFade = Math.min(1, this.selectionFade + dt / N.fade);
    let unsettled = this.selectionFade < 1 ? 1 : 0;
    const placed: Card[] = [];
    const ordered = [...this.cards.values()].sort(
      (a, b) => Number(b.clip.id === PHONE_ID) - Number(a.clip.id === PHONE_ID),
    );
    for (const c of ordered) {
      const phone = c.clip.id === PHONE_ID,
        selected = c.clip.id === this.selected;
      const a = this.anchor(c.slot),
        width = phone ? 72 : Math.min(158, Math.max(130, this.width * 0.32));
      const target = phone
        ? 72 * 1.61803398875
        : c.clip.kind === "image"
          ? selected
            ? 128
            : 98
          : selected
            ? 112
            : 74;
      c.height = reduced ? target : c.height + (target - c.height) * blend;
      unsettled += Math.abs(target - c.height);
      c.width = width;
      c.x = clamp(a.x - width / 2, 8, this.width - width - 8);
      c.y = a.y + N.drops[c.slot % 8];
      for (const prior of placed)
        if (
          c.x - 6 < prior.x + prior.width &&
          c.x + width + 6 > prior.x &&
          c.y - 6 < prior.y + prior.height &&
          c.y + c.height + 6 > prior.y
        )
          c.y = prior.y + prior.height + 9;
      c.y = clamp(c.y, 8, this.height - c.height - 8);
      placed.push(c);
      const p = clamp((elapsed - c.slot * N.stagger) / N.incoming, 0, 1);
      c.fold =
        phone || reduced ? 1 : Math.max(0.025, Math.sin((p * Math.PI) / 2));
      c.tilt = reduced
        ? 0
        : N.tilts[c.slot % 8] +
          (phone ? 0 : this.direction * 5 * Math.sin(p * Math.PI));
      c.opacity = phone ? 1 : reduced ? clamp(elapsed / N.fade, 0, 1) : p;
      c.el.style.setProperty(
        "--body-lines",
        String(
          Math.max(1, Math.floor((c.height - 37 - (selected ? 15 : 0)) / 15.5)),
        ),
      );
      c.el.classList.toggle("is-selected", selected);
      c.el.setAttribute("aria-pressed", String(selected));
      Object.assign(c.el.style, {
        left: `${c.x}px`,
        top: `${c.y}px`,
        width: `${width}px`,
        height: `${c.height}px`,
        transform: `rotate(${c.tilt}deg) scaleX(${c.fold})`,
        opacity: String(this.hiddenPaper === c.clip.id ? 0 : c.opacity),
      });
      c.el.inert = this.hiddenPaper === c.clip.id;
      c.el.disabled = !phone && elapsed < N.pageDuration;
      c.cord.setAttribute(
        "d",
        `M ${a.x} ${a.y} C ${a.x} ${(a.y + c.y + 7) / 2} ${c.x + width / 2} ${c.y - 3} ${c.x + width / 2} ${c.y + 7} M ${a.x - 2} ${a.y} a 2 2 0 1 0 4 0 a 2 2 0 1 0 -4 0`,
      );
      c.cord.style.opacity = String(c.opacity);
      if (selected) {
        const targetPose = {
          x: c.x - 2,
          y: c.y - 2,
          width: width + 4,
          height: c.height + 4,
          angle: c.tilt,
          inset: 7,
        };
        if (!this.ringPose || reduced) this.ringPose = targetPose;
        else
          for (const key of ["x", "y", "width", "height", "angle"] as const) {
            const old = this.ringPose[key];
            this.ringPose[key] += (targetPose[key] - old) * blend;
            unsettled += Math.abs(old - targetPose[key]);
          }
      }
    }
    for (const c of this.outgoing) {
      const p = clamp(elapsed / N.outgoing, 0, 1);
      c.el.style.opacity = String(c.opacity * (1 - p));
      c.el.style.transform = `translateX(${-this.direction * 8 * p}px) rotate(${c.tilt}deg) scaleX(${reduced ? 1 : c.fold * Math.max(0.02, Math.cos((p * Math.PI) / 2))})`;
    }
    if (elapsed >= N.outgoing && this.outgoing.length) {
      this.outgoing.forEach((c) => c.el.remove());
      this.outgoing = [];
    }
    if (this.ringPose) {
      const r = this.ringPose;
      Object.assign(this.ring.style, {
        left: `${r.x}px`,
        top: `${r.y}px`,
        width: `${r.width}px`,
        height: `${r.height}px`,
        transform: `rotate(${r.angle}deg)`,
      });
    }
    this.ring.style.opacity =
      this.selected && this.selected !== this.hiddenPaper && this.visible
        ? String(clamp(elapsed / N.incoming, 0, 1) * this.selectionFade)
        : "0";
    this.onLayout();
    if (elapsed < N.pageDuration || unsettled > 0.05)
      this.frame = requestAnimationFrame((t) => this.tick(t));
  }
}
