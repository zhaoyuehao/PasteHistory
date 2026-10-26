export type Clip = {
  id: string;
  kind: "text" | "image" | "file";
  text: string;
  source: string;
  created: number;
  pinned: boolean;
  image?: string;
  ocr?: string;
  paths?: string[];
};
export const PAGE_SIZE = 8;
export class HistoryStore {
  clips: Clip[];
  query = "";
  selectedId: string | null;
  preview = false;
  visible = true;
  constructor(clips: Clip[]) {
    this.clips = clips.map((c) => ({ ...c }));
    this.selectedId = this.results[0]?.id ?? null;
  }
  get results() {
    const q = this.query.toLocaleLowerCase().trim();
    return this.clips
      .filter((c) =>
        `${c.text} ${c.source} ${c.ocr ?? ""} ${c.paths?.join(" ") ?? ""}`
          .toLocaleLowerCase()
          .includes(q),
      )
      .sort(
        (a, b) => Number(b.pinned) - Number(a.pinned) || b.created - a.created,
      );
  }
  get selected() {
    return this.results.find((c) => c.id === this.selectedId);
  }
  get index() {
    return this.results.findIndex((c) => c.id === this.selectedId);
  }
  get page() {
    return Math.max(0, Math.floor(this.index / PAGE_SIZE));
  }
  get pages() {
    return Math.max(1, Math.ceil(this.results.length / PAGE_SIZE));
  }
  get entries() {
    return this.results.slice(
      this.page * PAGE_SIZE,
      (this.page + 1) * PAGE_SIZE,
    );
  }
  search(query: string) {
    this.query = query;
    this.selectedId = this.results[0]?.id ?? null;
    if (!this.selected) this.preview = false;
  }
  select(id: string, preview = false) {
    if (this.results.some((c) => c.id === id)) {
      this.selectedId = id;
      if (preview) this.preview = true;
    }
  }
  move(delta: number) {
    const r = this.results;
    this.selectedId =
      r[Math.max(0, Math.min(r.length - 1, this.index + delta))]?.id ?? null;
  }
  turn(delta: number) {
    this.move(delta * PAGE_SIZE);
  }
  pin() {
    const c = this.selected;
    if (c) c.pinned = !c.pinned;
  }
  remove() {
    const index = this.index;
    this.clips = this.clips.filter((c) => c.id !== this.selectedId);
    this.selectedId =
      this.results[Math.max(0, Math.min(index - 1, this.results.length - 1))]
        ?.id ?? null;
    if (!this.selected) this.preview = false;
  }
  add(clip: Clip) {
    this.clips = this.clips.filter(
      (c) => !(c.text === clip.text && c.kind === clip.kind),
    );
    this.clips.unshift(clip);
    this.query = "";
    this.selectedId = clip.id;
  }
}
