import "./style.css";
import "./native.css";
import { HistoryStore, type Clip } from "./store";
import { initialClips, sampleImage, sampleLanguages } from "./fixtures";
import { TreeStage } from "./tree";
import { TreeEntrance } from "./entrance";
import { NativePreview } from "./preview";
import { PHI, PHONE_ID, dateLabel } from "./native";
import { loadStats, REPO, type Stats } from "./github";
import {
  t,
  locale,
  setLocale,
  locales,
  bindLabels,
  refreshLabels,
} from "./i18n";
const $ = <T extends HTMLElement = HTMLElement>(selector: string) =>
  document.querySelector<T>(selector)!;
const icons = {
  tree: '<path d="M12 21V3m0 8L6 5m6 10 7-8m-7 11-8-6"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V4H4v12h4"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  github:
    '<path d="M9 19c-4 1-4-2-6-2m12 5v-4c0-1-.3-2-1-2 4 0 7-2 7-6 0-2-.5-3-1.5-4 .3-1 .3-3-.5-4-2 0-3 1-4 2a13 13 0 0 0-6 0C8 3 7 2 5 2c-.8 1-1 3-.5 4C3.5 7 3 8 3 10c0 4 3 6 7 6-.7.5-1 1-1 2v4"/>',
  star: '<path d="m12 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
  note: '<rect x="4" y="3" width="16" height="19" rx="3"/><path d="M4 8h16M8 12h8m-8 4h6"/>',
  compass: '<circle cx="12" cy="12" r="9"/><path d="m16 8-3 5-5 3 3-5Z"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-11v2"/>',
  pin: '<path d="m8 3 8 0-1 6 4 4H5l4-4-1-6m4 10v9"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
};
const icon = (name: keyof typeof icons) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;
const lights = () =>
  `<div class="traffic" aria-hidden="true"><span class="red"></span><span class="yellow"></span><span class="green"></span></div>`;
$("#app").innerHTML = `
<div class="desktop native-desktop exploring" data-mobile-view="tree">
 <div class="wallpaper" aria-hidden="true"></div>
 <header class="menubar"><button class="brand" id="menu-tree">${icon("tree")}<b>PasteHistory</b></button><div class="menu-spacer"></div><label class="language-control"><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.5"/><ellipse cx="10" cy="10" rx="3.2" ry="7.5"/><path d="M2.5 10h15"/></svg><span id="language-name" aria-hidden="true"></span><svg class="language-chevron" viewBox="0 0 12 12" aria-hidden="true"><path d="m3 4.5 3 3 3-3"/></svg><select id="site-language" aria-label="语言"></select></label><span class="system-status" aria-hidden="true">⌁ &nbsp; ▰</span><time id="clock"></time></header>
 <main id="desktop-main">
  <section class="hero-heading"><p>PasteHistory</p><h1>复制过的，随时找回。</h1></section>
  <section id="tree-area" aria-label="许愿树剪贴板"><div id="tree-stage"></div><div id="empty" hidden>枝头暂时空了。<br><small>换个关键词，或复制一条新灵感。</small></div><p class="tree-hint">点一张纸签，试试看。</p><div class="tree-controls"><span class="search-cord"></span><div class="search-tag"><span class="search-hole"></span>${icon("search")}<input id="search" aria-label="搜索剪贴板" autocomplete="off" spellcheck="false"><span id="page-label"></span></div></div></section>
  <section class="download-area" aria-label="下载 PasteHistory"><a id="download-button" class="download-button" tabindex="0" role="link" aria-disabled="true">${icon("download")}<span id="download-label">下载 Mac 版</span></a><p>Apple Silicon · macOS 14+</p><small>预览版 · 未经 Apple 公证</small><small id="download-state" role="status" aria-live="polite"></small></section>
  <section id="browser" class="window browser-window" aria-label="复制样例"><div class="titlebar">${lights()}<span>复制样例</span></div><div class="browser-body"><div id="sample-content"></div></div></section>
  <section id="notes" class="window notes-window" aria-label="备忘录"><div class="titlebar"><div class="traffic" aria-hidden="true"><span class="red"></span><span class="yellow"></span><span class="green"></span></div><span>备忘录</span><button id="clear-note" aria-label="清空备忘录">${icon("trash")}</button></div><div class="notes-body"><div id="note-editor" role="textbox" aria-label="备忘录内容" contenteditable="true" aria-multiline="true" data-placeholder="拖到这里，或直接粘贴。"></div></div><span id="note-status" class="sr-only" role="status" aria-live="polite"></span></section>
 </main>
 <footer class="site-footer"><a href="${REPO}" target="_blank" rel="noopener" class="github-link">${icon("github")} GitHub</a><a href="${REPO}" target="_blank" rel="noopener" class="repo-url">github.com/zhaoyuehao/PasteHistory</a><div class="stats"><a id="stars" href="${REPO}/stargazers" target="_blank" rel="noopener">Star <span>—</span></a><span id="downloads">下载次数 <span>—</span></span></div></footer>

 <div id="preview" class="preview" hidden aria-label="纸签预览"><div class="preview-compact"></div><div class="preview-face"><div class="preview-hole"></div><div class="preview-heading"><span id="preview-source"></span></div><div id="preview-content"></div><div id="preview-date"></div></div></div>
 <div id="toast" role="status" aria-live="polite"></div>
</div>`;
const store = new HistoryStore(initialClips());

// Site navigation stays outside the simulated screen. Product actions never
// resize the tree or reveal a second layout.
const screen = $("#desktop-main");
$(".desktop").prepend($(".wallpaper"));
screen.prepend($(".menubar"));
const rootLinks = document.createElement("section");
rootLinks.className = "root-links";
rootLinks.setAttribute("aria-label", "下载与 GitHub");
rootLinks.append($(".download-area"), $(".site-footer"));
$(".desktop").append(rootLinks);
function placeRootLinks() {
  const tag = $(".tree-controls").getBoundingClientRect();
  const desktop = $(".desktop").getBoundingClientRect();
  const width = rootLinks.offsetWidth;
  const x = Math.max(
    width / 2 + 12,
    Math.min(
      desktop.width - width / 2 - 12,
      tag.left + tag.width / 2 - desktop.left,
    ),
  );
  const y = Math.min(
    tag.bottom -
      desktop.top +
      (parseFloat(
        getComputedStyle($(".desktop")).getPropertyValue("--composition-gap"),
      ) || 12),
    desktop.height - rootLinks.offsetHeight - 16,
  );
  rootLinks.style.left = `${x}px`;
  rootLinks.style.top = `${Math.max(42, y)}px`;
}
new ResizeObserver(() => {
  placeNativeTree();
  placeRootLinks();
}).observe(rootLinks);
$(".hero-heading").remove();
$(".tree-hint").remove();
const notesRail = document.createElement("aside");
notesRail.className = "notes-rail";
const shortcuts = document.createElement("section");
shortcuts.className = "shortcut-guide";
shortcuts.setAttribute("aria-label", "常用快捷键");
shortcuts.innerHTML = `<dl><div><dt>↑ ↓</dt><dd>选择</dd></div><div><dt>Space</dt><dd>预览</dd></div><div><dt>↵</dt><dd>粘贴</dd></div><div><dt>⇧⌘V</dt><dd>打开许愿树</dd></div></dl>`;
$(".notes-body").append(shortcuts);
notesRail.append($("#notes"));
$(".desktop").append(notesRail);
const samplesRail = document.createElement("aside");
samplesRail.className = "samples-rail";
samplesRail.append($("#browser"));
$(".desktop").append(samplesRail);
const reopenTree = document.createElement("button");
reopenTree.id = "reopen-tree";
reopenTree.setAttribute("aria-keyshortcuts", "Meta+Shift+V");
reopenTree.innerHTML = `<span>找回复制过的内容</span><kbd>⌘ ⇧ V</kbd><small>按快捷键或点这里，打开许愿树</small>`;
reopenTree.onclick = presentTree;
screen.append(reopenTree);
function enterExperience() {
  $(".desktop").classList.add("exploring");
  $(".tree-controls").inert = false;
}
const sampleDrafts = new Map<string, string>();
const languageSelect = $<HTMLSelectElement>("#site-language");
for (const [code, label] of locales) {
  const option = document.createElement("option");
  option.value = code;
  option.textContent = label;
  languageSelect.append(option);
}
languageSelect.value = locale;
function updateLanguageName() {
  $("#language-name").textContent = locales.find(
    ([code]) => code === locale,
  )![1];
}
updateLanguageName();
let lastStats: { stats: Stats | null; stale: boolean } | null = null;
languageSelect.onchange = () => applyLanguage();
function applyLanguage() {
  const editor = $<HTMLTextAreaElement>("#sample-text");
  if (editor) sampleDrafts.set(locale, editor.value);
  setLocale(languageSelect.value);
  refreshLabels();
  updateLanguageName();
  document.title = `PasteHistory — ${t("复制过的，随时找回。")}`;
  document
    .querySelector('meta[name="description"]')
    ?.setAttribute("content", t("复制过的，随时找回。"));
  const fixtures = new Map(initialClips().map((clip) => [clip.id, clip]));
  // Only localize fixture records; user drafts, collected records and Notes are content.
  store.clips = store.clips.map((clip) => {
    const translated = fixtures.get(clip.id);
    return translated
      ? { ...translated, created: clip.created, pinned: clip.pinned }
      : clip;
  });
  if (!store.selected) store.selectedId = store.results[0]?.id ?? null;
  displaySample();
  updateNoteStatus();
  previewId = null;
  render();
  clock();
  renderStats();
  placeRootLinks();
}
let composing = false;
let keyboardCards = false;
let draggingCard = false;
let noteRange: Range | null = null;
let pasteTarget: HTMLElement | null = null;
let inputRange = { start: 0, end: 0 };
function captureInputTarget() {
  const active = document.activeElement;
  if (active instanceof HTMLTextAreaElement && active.id === "sample-text") {
    pasteTarget = active;
    inputRange = { start: active.selectionStart, end: active.selectionEnd };
  } else if (active instanceof HTMLElement && active.id === "note-editor")
    pasteTarget = active;
}
document.addEventListener("focusin", captureInputTarget);
document.addEventListener("selectionchange", captureInputTarget);
document.addEventListener("focusout", captureInputTarget, true);
let toastTimer: ReturnType<typeof setTimeout>;
let downloadPending = false;
let downloadRequested = false;
// One golden-ratio composition owns window sizes, spacing and placement.

function placeNativeTree() {
  const desktop = $(".desktop");
  const viewportWidth = desktop.clientWidth;
  const menuHeight = $(".menubar").offsetHeight;
  const stacked = viewportWidth < 760;
  const rootHeight = rootLinks.offsetHeight;
  const logicalWidth = 880;
  const logicalHeight = 920;
  let treeWidth: number;
  let treeTop: number;
  let treeLeft: number;
  let windowWidth: number;
  let samplesTop: number;
  let notesTop: number;
  let samplesLeft: number;
  let notesLeft: number;
  let gap: number;
  if (stacked) {
    const margin = 16;
    windowWidth = Math.min(viewportWidth - margin * 2, 377);
    gap = windowWidth / PHI ** 4;
    treeWidth = Math.min(viewportWidth - margin * 2, logicalWidth);
    treeTop = menuHeight + gap;
    treeLeft = (viewportWidth - treeWidth) / 2;
    samplesLeft = notesLeft = (viewportWidth - windowWidth) / 2;
    samplesTop =
      treeTop +
      (treeWidth * logicalHeight) / logicalWidth +
      rootHeight +
      gap * 2;
    notesTop = samplesTop + windowWidth * PHI + gap;
    desktop.style.height = `${notesTop + windowWidth * PHI + gap}px`;
  } else {
    desktop.style.removeProperty("height");
    const viewportHeight = desktop.clientHeight;
    const availableHeight = viewportHeight - menuHeight;
    // Size the sculpture from available height, not from the small side windows.
    // The exported 880 pt frame contains transparent side margins. Reserve its
    // central 660 pt band (including every paper) when positioning adjacent UI.
    const occupiedFraction = 660 / logicalWidth;
    windowWidth = Math.min(230, Math.max(180, viewportWidth * 0.17));
    gap = windowWidth / PHI ** 4;
    const minimumOuter = gap * PHI;
    treeWidth = Math.min(
      (viewportWidth - 2 * windowWidth - 2 * gap - 2 * minimumOuter) /
        occupiedFraction,
      ((availableHeight - rootHeight - 24) * logicalWidth) / logicalHeight,
    );
    const occupiedWidth = treeWidth * occupiedFraction;
    const treeHeight = (treeWidth * logicalHeight) / logicalWidth;
    const groupHeight = treeHeight + 12 + rootHeight;
    treeTop = menuHeight + (availableHeight - groupHeight) / PHI ** 2;
    treeLeft = (viewportWidth - treeWidth) / 2;
    samplesLeft = (viewportWidth - occupiedWidth) / 2 - gap - windowWidth;
    notesLeft = (viewportWidth + occupiedWidth) / 2 + gap;
    samplesTop = notesTop = treeTop + (treeHeight - windowWidth * PHI) / 2;
  }
  const windowHeight = windowWidth * PHI;
  for (const [rail, left, top] of [
    [samplesRail, samplesLeft, samplesTop],
    [notesRail, notesLeft, notesTop],
  ] as const) {
    Object.assign(rail.style, {
      width: `${windowWidth}px`,
      height: `${windowHeight}px`,
      left: `${left}px`,
      top: `${top}px`,
      right: "auto",
    });
  }
  desktop.style.setProperty("--composition-gap", "12px");
  Object.assign($("#tree-area").style, {
    width: `${logicalWidth}px`,
    height: `${logicalHeight}px`,
    left: `${treeLeft}px`,
    top: `${treeTop}px`,
    transform: `scale(${treeWidth / logicalWidth})`,
    transformOrigin: "0 0",
  });
  Object.assign(reopenTree.style, {
    width: `${Math.min(330, treeWidth - 16)}px`,
    left: `${treeLeft + treeWidth / 2}px`,
    top: `${treeTop + (treeWidth * logicalHeight) / logicalWidth / 2}px`,
  });
}

placeNativeTree();
window.addEventListener("resize", () => {
  placeNativeTree();
  placeRootLinks();
});
new ResizeObserver(placeNativeTree).observe(samplesRail);
new ResizeObserver(placeNativeTree).observe(notesRail);
const tree = new TreeStage($("#tree-stage"));
const note = $("#note-editor");
let noteStatus = "粘贴目标 · 保留光标位置";
function updateNoteStatus(key = noteStatus) {
  noteStatus = key;
  $("#note-status").textContent = t(key);
}
const search = $<HTMLInputElement>("#search");
const preview = $("#preview");
let previewId: string | null = null;
let previewSize = { width: 340, height: 210 };
let phoneSelected = false;
const nativePreview = new NativePreview(preview, () => {
  const r = screen.getBoundingClientRect();
  return { left: r.left, top: r.top + 30, right: r.right, bottom: r.bottom };
});
const treeEntrance = new TreeEntrance($("#tree-area"));
treeEntrance.onLayout = () => {
  updatePreview();
  placeRootLinks();
};
nativePreview.onClosed = () => {
  tree.conceal(null);
  previewId = null;
};
nativePreview.onCollapse = () => {
  store.preview = false;
  focusSearch();
  render();
};
function focusSearch() {
  search.focus({ preventScroll: true });
}
function presentTree() {
  captureInputTarget();
  if (store.visible) {
    focusSearch();
    return;
  }
  enterExperience();
  store.visible = true;
  store.preview = false;
  phoneSelected = false;
  store.selectedId = store.results[0]?.id ?? null;
  keyboardCards = false;
  $(".desktop").dataset.mobileView = "tree";
  placeNativeTree();
  render();
  focusSearch();
}
function closeTree() {
  store.preview = false;
  store.visible = false;
  render();
  search.blur();
  const target = pasteTarget;
  if (target?.isConnected && !target.closest(".minimized")) {
    target.focus({ preventScroll: true });
    if (target instanceof HTMLTextAreaElement)
      target.setSelectionRange(inputRange.start, inputRange.end);
    else if (noteRange && note.contains(noteRange.commonAncestorContainer)) {
      const selection = getSelection();
      selection?.removeAllRanges();
      selection?.addRange(noteRange);
    }
  }
}
function togglePreview() {
  if (!store.selected && !phoneSelected) return;
  enterExperience();
  store.preview = !store.preview;
  focusSearch();
  render();
}
function toast(message: string) {
  $("#toast").textContent = t(message);
  $("#toast").classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 2600);
}
function displaySample() {
  const host = $("#sample-content");
  const language = sampleLanguages.find((l) => l.code === locale)!;
  host.replaceChildren();
  for (const kind of ["text", "image"] as const) {
    const sample = document.createElement("section");
    sample.className = "sample-item";
    if (kind === "text") {
      const editor = document.createElement("textarea");
      editor.id = "sample-text";
      editor.setAttribute("aria-label", t("可复制的示例文字"));
      editor.value = sampleDrafts.get(locale) ?? language.text;
      editor.lang = locale;
      editor.oninput = () => sampleDrafts.set(locale, editor.value);
      sample.append(editor);
    } else {
      const image = document.createElement("img");
      image.src = sampleImage;
      image.alt = language.image;
      sample.append(image);
    }
    const button = document.createElement("button");
    button.className = "collect-button";
    button.dataset.copy = kind;
    button.innerHTML = `${icon("copy")}<span></span>`;
    button.querySelector("span")!.textContent = t("复制");
    button.setAttribute(
      "aria-label",
      t(kind === "text" ? "复制文字" : "复制图片"),
    );
    button.onclick = () => collect(kind);
    sample.append(button);
    host.append(sample);
  }
}
function syncInteraction() {
  $("#tree-area").inert = !store.visible;
}
function showWindow(name: string) {
  enterExperience();
  if (name === "tree") return presentTree();
  if (store.visible) closeTree();
  const target = name === "notes" ? note : $("#sample-text");
  target?.focus({ preventScroll: true });
  if (name === "notes") pasteTarget = note;
  if (innerWidth < 760) {
    const rail = name === "notes" ? notesRail : samplesRail;
    window.scrollTo({
      top: rail.getBoundingClientRect().top + scrollY - 16,
      behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "instant"
        : "smooth",
    });
  }
}
function collect(sampleKind: "text" | "image") {
  const language = sampleLanguages.find((l) => l.code === locale)!;
  const clip: Clip = {
    id: crypto.randomUUID(),
    kind: sampleKind,
    text:
      sampleKind === "text"
        ? $<HTMLTextAreaElement>("#sample-text").value
        : language.image,
    lang: locale,
    source: "Safari",
    created: Date.now(),
    pinned: false,
    ...(sampleKind === "image" ? { image: sampleImage } : {}),
  };
  if (!clip.text.trim()) {
    toast("先写下一点灵感吧");
    return;
  }
  store.add(clip);
  store.preview = false;
  store.visible = true;
  search.value = "";
  keyboardCards = true;
  showWindow("tree");
  render();
  toast("已收藏到许愿树");
  syncInteraction();
}
function render() {
  tree.render(
    store.entries,
    phoneSelected ? PHONE_ID : store.selectedId,
    store.preview || nativePreview.isVisible,
    store.visible,
    store.page * 8,
  );
  treeEntrance.show(store.visible);
  reopenTree.classList.toggle("visible", !store.visible);
  reopenTree.inert = store.visible;
  reopenTree.setAttribute("aria-hidden", String(store.visible));
  $("#tree-area").classList.toggle("closed", !store.visible);
  $("#empty").hidden = store.results.length > 0;
  $("#page-label").textContent = store.results.length
    ? `${store.page + 1} / ${store.pages} · ${store.results.length}`
    : "0 / 0";
  syncInteraction();
  updatePreview();
}
function select(id: string) {
  phoneSelected = id === PHONE_ID;
  if (phoneSelected) store.preview = true;
  else store.select(id, true);
  enterExperience();
  focusSearch();
  keyboardCards = true;
  render();
}
tree.onSelect = select;
tree.onFocus = () => {
  captureInputTarget();
  focusSearch();
};
tree.onDragEnd = () => {
  draggingCard = false;
  if (store.visible) focusSearch();
};
tree.onDrag = () => {
  draggingCard = true;
  nativePreview.dismissImmediately();
  enterExperience();
  store.preview = false;
  render();
};
function updatePreview() {
  const clip = phoneSelected ? undefined : store.selected;
  const id = phoneSelected ? PHONE_ID : (clip?.id ?? null);
  const want = !!(store.preview && id && store.visible);
  const contentChanged = want && id !== previewId;
  if (contentChanged) {
    previewId = id;
    $("#preview-source").textContent = phoneSelected
      ? t("手机同步")
      : `${String(store.index + 1).padStart(2, "0")}${clip?.pinned ? " · ↟" : ""} · ${clip?.source || "—"}`;
    $("#preview-date").textContent = clip
      ? dateLabel(clip.created)
      : t("网页演示 · 未连接设备");
    const content = $("#preview-content");
    content.replaceChildren();
    content.lang = clip?.lang ?? locale;
    content.classList.toggle("image-content", !!clip?.image);
    if (phoneSelected) {
      const p = document.createElement("p");
      p.textContent = t(
        "手机同步\n\nMac 版可以通过局域网与手机配对。网页体验不连接真实设备，也不生成配对二维码。",
      );
      content.append(p);
    } else if (clip) {
      if (clip.image) {
        const img = document.createElement("img");
        img.src = clip.image;
        img.alt = clip.text;
        content.append(img);
        if (clip.ocr) {
          const label = document.createElement("small");
          label.textContent = t("预置 OCR 示例文字");
          content.append(label);
        }
      }
      if (clip.kind === "file" && !clip.image) {
        const files = document.createElement("div");
        files.className = "preview-files";
        for (const path of clip.paths ?? [clip.text]) {
          const row = document.createElement("div");
          row.className = "preview-file-row";
          const glyph = document.createElement("span");
          glyph.className = "file-glyph";
          glyph.textContent =
            path.split(".").pop()?.toUpperCase().slice(0, 4) ?? "FILE";
          const labels = document.createElement("div");
          const name = document.createElement("div");
          name.textContent = path.split("/").pop() ?? path;
          const directory = document.createElement("small");
          directory.textContent = path.includes("/")
            ? path.slice(0, path.lastIndexOf("/"))
            : t("演示文件");
          labels.append(name, directory);
          row.append(glyph, labels);
          files.append(row);
        }
        content.append(files);
      }
      if ((!clip.image && clip.kind !== "file") || clip.ocr) {
        const p = document.createElement("p");
        p.textContent = clip.image ? clip.ocr! : clip.text;
        content.append(p);
      }
    }
    content.scrollTop = 0;
  }
  if (contentChanged) {
    let size = { width: 340, height: 210 };
    if (phoneSelected) size = { width: 340, height: 390 };
    else if (clip?.image) size = { width: 480, height: 297 };
    else if (clip?.kind === "file") size = { width: 400, height: 247 };
    else if (clip) {
      // Measure the same fixed logical reading layouts used by PreviewPanel.
      const measure = document.createElement("div");
      Object.assign(measure.style, {
        position: "fixed",
        visibility: "hidden",
        font: "15px -apple-system, BlinkMacSystemFont, sans-serif",
        lineHeight: "normal",
        whiteSpace: "pre-wrap",
        overflowWrap: "anywhere",
      });
      measure.textContent = clip.text.slice(0, 3000);
      document.body.append(measure);
      for (const candidate of [
        { width: 340, height: 210 },
        { width: 400, height: 247 },
        { width: 480, height: 297 },
      ]) {
        size = candidate;
        measure.style.width = `${candidate.width - 42}px`;
        if (measure.offsetHeight + 84 <= candidate.height) break;
      }
      measure.remove();
    }
    previewSize = size;
  }
  nativePreview.update(
    id,
    id ? tree.pose(id) : undefined,
    want,
    previewSize,
    () => (id ? tree.compact(id) : undefined),
  );
}
tree.onLayout = () => {
  updatePreview();
  placeRootLinks();
};
function rememberSelection() {
  const s = getSelection();
  if (s?.rangeCount && note.contains(s.anchorNode))
    noteRange = s.getRangeAt(0).cloneRange();
}
document.addEventListener("selectionchange", rememberSelection);
function clipboardText(clip: Clip) {
  return clip.paths?.join("\n") ?? clip.text;
}
function paste(clip = phoneSelected ? undefined : store.selected) {
  if (!clip) return;
  const target = pasteTarget?.isConnected ? pasteTarget : note;
  if (target instanceof HTMLTextAreaElement && !clip.image) {
    showWindow("browser");
    target.focus();
    target.setRangeText(
      clipboardText(clip),
      inputRange.start,
      inputRange.end,
      "end",
    );
    inputRange = { start: target.selectionStart, end: target.selectionEnd };
    store.preview = false;
    store.visible = false;
    render();
    toast("已粘贴到原输入位置");
    return;
  }
  insertIntoNotes([clip]);
}
const noteObjectURLs = new Set<string>();
function clearNotes() {
  note.replaceChildren();
  noteRange = null;
  for (const url of noteObjectURLs) URL.revokeObjectURL(url);
  noteObjectURLs.clear();
}
function imageFiles(files: File[]): Clip[] {
  return files
    .filter((file) => /^image\/(png|jpeg|gif|webp|avif|bmp)$/.test(file.type))
    .map((file) => {
      const image = URL.createObjectURL(file);
      noteObjectURLs.add(image);
      return {
        id: crypto.randomUUID(),
        kind: "image",
        text: file.name || t("粘贴的图片"),
        image,
        source: t("本次粘贴"),
        created: Date.now(),
        pinned: false,
      };
    });
}
function insertIntoNotes(clips: Clip[], position: Range | null = noteRange) {
  if (!clips.length) return;
  // Capture the insertion point before focus restoration changes the selection.
  let range: Range;
  if (position && note.contains(position.commonAncestorContainer))
    range = position.cloneRange();
  else {
    range = document.createRange();
    range.selectNodeContents(note);
    range.collapse(false);
  }
  showWindow("notes");
  pasteTarget = note;
  range.deleteContents();
  const fragment = document.createDocumentFragment();
  for (const clip of clips) {
    if (clip.image) {
      const img = document.createElement("img");
      img.src = clip.image;
      img.alt = clip.text;
      img.className = "note-image";
      img.draggable = false;
      img.addEventListener("error", () => {
        img.replaceWith(
          document.createTextNode(`[${t("图片无法显示")}: ${clip.text}]`),
        );
      });
      fragment.append(img, document.createElement("br"));
    } else fragment.append(document.createTextNode(clipboardText(clip)));
  }
  const end = document.createTextNode("");
  fragment.append(end);
  range.insertNode(fragment);
  range.setStartAfter(end);
  range.collapse(true);
  note.focus({ preventScroll: true });
  const selection = getSelection();
  selection?.removeAllRanges();
  selection?.addRange(range);
  noteRange = range;
  updateNoteStatus(
    clips.some((clip) => clip.image) ? "图片已放入备忘录" : "已粘贴到备忘录",
  );
  store.preview = false;
  store.visible = false;
  render();
}

async function realCopy() {
  const clip = store.selected;
  if (!clip || phoneSelected) return;
  closeTree();
  try {
    if (clip.image && typeof ClipboardItem !== "undefined") {
      // Keep write() inside the user gesture, including Safari's activation window.
      const png = (async () => {
        const response = await fetch(clip.image!);
        if (!response.ok) throw new Error("image unavailable");
        const bitmap = await createImageBitmap(await response.blob());
        const canvas = document.createElement("canvas");
        canvas.width = bitmap.width;
        canvas.height = bitmap.height;
        canvas.getContext("2d")!.drawImage(bitmap, 0, 0);
        bitmap.close();
        return await new Promise<Blob>((resolve, reject) =>
          canvas.toBlob(
            (blob) =>
              blob ? resolve(blob) : reject(new Error("PNG unavailable")),
            "image/png",
          ),
        );
      })();
      await navigator.clipboard.write([
        new ClipboardItem({ "image/png": png }),
      ]);
    } else if (clip.image) {
      throw new Error("image clipboard unavailable");
    } else await navigator.clipboard.writeText(clipboardText(clip));
    toast("已复制到系统剪贴板");
  } catch {
    toast("浏览器未允许复制；仍可粘贴到演示备忘录");
  }
}
function deleteSelected() {
  if (!store.selected || phoneSelected) return;
  store.remove();
  previewId = null;
  render();
  toast("纸签已删除");
}
const statsSnapshot = `${import.meta.env.BASE_URL}github-stats.json`;
function renderDownload() {
  const link = $<HTMLAnchorElement>("#download-button");
  const stats = lastStats?.stats;
  if (stats?.downloadUrl) link.href = stats.downloadUrl;
  else link.removeAttribute("href");
  link.setAttribute(
    "aria-disabled",
    String(!stats?.downloadUrl || downloadPending),
  );
  link.setAttribute("aria-busy", String(downloadPending));
  link.title = stats?.version ?? "";
  $("#download-label").textContent = t(
    downloadPending ? "正在获取下载…" : "下载 Mac 版",
  );
  $("#download-state").textContent =
    downloadPending || !lastStats || stats?.downloadUrl
      ? ""
      : t(stats ? "安装包尚未发布" : "下载暂不可用");
}
$("#download-button").onkeydown = (event) => {
  if (event.key === "Enter" && !$("#download-button").hasAttribute("href")) {
    event.preventDefault();
    $("#download-button").click();
  }
};
$("#download-button").onclick = async (event) => {
  // Preserve ordinary link behavior for a known attachment when opening a new tab.
  if (
    (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) &&
    lastStats?.stats?.downloadUrl
  )
    return;
  event.preventDefault();
  if (downloadPending) return;
  downloadRequested = true;
  downloadPending = true;
  renderDownload();
  try {
    // Download clicks bypass the statistics cache so newly published versions win.
    lastStats = await loadStats(statsSnapshot, { refresh: true });
    renderStats();
    const url = lastStats.stats?.downloadUrl;
    if (url) {
      if (lastStats.stale) toast("无法检查更新，将下载已知版本");
      window.location.assign(url);
    }
  } finally {
    downloadPending = false;
    renderDownload();
  }
};
search.addEventListener("input", () => {
  if (composing) return;
  store.search(search.value);
  phoneSelected = false;
  keyboardCards = false;
  render();
});
search.addEventListener("focus", () => (keyboardCards = false));
search.addEventListener("pointerdown", () => (keyboardCards = false));
$("#menu-tree").onclick = () => (store.visible ? closeTree() : presentTree());
$("#clear-note").onclick = () => {
  clearNotes();
  updateNoteStatus("粘贴目标 · 保留光标位置");
};
const notesWindow = $("#notes");
notesWindow.addEventListener("dragover", (e) => {
  e.preventDefault();
  if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
  notesWindow.classList.add("drop-ready");
});
notesWindow.addEventListener("dragleave", (e) => {
  if (!notesWindow.contains(e.relatedTarget as Node))
    notesWindow.classList.remove("drop-ready");
});
notesWindow.addEventListener("drop", (e) => {
  e.preventDefault();
  notesWindow.classList.remove("drop-ready");
  const transfer = e.dataTransfer;
  if (!transfer) return;
  const range = document.caretRangeFromPoint?.(e.clientX, e.clientY);
  const point =
    range && note.contains(range.startContainer) ? range : noteRange;
  const clip = store.clips.find(
    (c) => c.id === transfer.getData("application/x-pastehistory"),
  );
  if (clip) {
    insertIntoNotes([clip], point);
    return;
  }
  const images = imageFiles(Array.from(transfer.files));
  if (images.length) {
    insertIntoNotes(images, point);
    return;
  }
  const text = transfer.getData("text/plain");
  if (text)
    insertIntoNotes(
      [
        {
          id: "drop",
          kind: "text",
          text,
          source: "拖入",
          created: Date.now(),
          pinned: false,
        },
      ],
      point,
    );
  else if (transfer.files.length)
    toast("可拖入 PNG、JPEG、GIF、WebP、AVIF 或 BMP 图片");
});
// Clipboard files are supplied by the user's paste event. Never import HTML or fetch its URLs.
note.addEventListener("paste", (e) => {
  const transfer = e.clipboardData;
  if (!transfer) return;
  e.preventDefault();
  const files = Array.from(transfer.items)
    .filter((item) => item.kind === "file")
    .map((item) => item.getAsFile())
    .filter((file): file is File => !!file);
  const images = imageFiles(files.length ? files : Array.from(transfer.files));
  if (images.length) {
    insertIntoNotes(images);
    return;
  }
  const text = transfer.getData("text/plain");
  if (text)
    insertIntoNotes([
      {
        id: "paste",
        kind: "text",
        text,
        source: "粘贴",
        created: Date.now(),
        pinned: false,
      },
    ]);
});
document.addEventListener("compositionstart", () => (composing = true));
document.addEventListener("compositionend", () => {
  composing = false;
  if (document.activeElement === search) {
    phoneSelected = false;
    keyboardCards = false;
    store.search(search.value);
    render();
  }
});
// PanelController + HistoryKeyboardState dispatch order. Browser/system shortcuts
// can be intercepted before keydown; all actions also have explicit controls.
document.addEventListener("keydown", (e) => {
  if (draggingCard || composing || e.isComposing || e.keyCode === 229) return;
  const target = e.target as HTMLElement;
  const editing =
    target.isContentEditable ||
    target instanceof HTMLTextAreaElement ||
    (target instanceof HTMLInputElement && target !== search);
  const command = e.metaKey;
  const commandOnly = command && !e.shiftKey && !e.altKey && !e.ctrlKey;
  const noModifiers = !command && !e.shiftKey && !e.altKey && !e.ctrlKey;
  if (command && e.shiftKey && !e.ctrlKey && !e.altKey && e.code === "KeyV") {
    e.preventDefault();
    if (!e.repeat) store.visible ? closeTree() : presentTree();
    return;
  }
  if (editing || !store.visible) return;
  if (
    target.closest(
      ".menubar,.download-area,.site-footer,#browser,#notes,#reopen-tree",
    )
  )
    return;
  if (e.key === "Escape") {
    e.preventDefault();
    if (e.repeat) return;
    if (store.preview) {
      store.preview = false;
      render();
    } else closeTree();
    return;
  }
  if (e.key === " " && e.shiftKey && !command && !e.ctrlKey && !e.altKey) {
    keyboardCards = false;
    if (target !== search) {
      e.preventDefault();
      focusSearch();
      search.setRangeText(
        " ",
        search.selectionStart ?? search.value.length,
        search.selectionEnd ?? search.value.length,
        "end",
      );
      search.dispatchEvent(new Event("input"));
    }
    return;
  }
  if (
    (e.key === " " && !command && !e.ctrlKey && !e.altKey) ||
    (commandOnly && e.code === "KeyY")
  ) {
    e.preventDefault();
    if (!e.repeat) togglePreview();
    return;
  }
  if (
    ["ArrowDown", "ArrowUp"].includes(e.key) ||
    (noModifiers && ["PageDown", "PageUp"].includes(e.key))
  ) {
    e.preventDefault();
    enterExperience();
    phoneSelected = false;
    focusSearch();
    keyboardCards = true;
    const previousId = store.selectedId;
    store.move(
      e.key === "ArrowDown"
        ? 1
        : e.key === "ArrowUp"
          ? -1
          : e.key === "PageDown"
            ? 8
            : -8,
    );
    if (previousId === store.selectedId && store.results.length)
      nativePreview.bounce(
        e.key === "ArrowDown" || e.key === "PageDown" ? -1 : 1,
      );
    render();
    return;
  }
  if (e.key === "Enter") {
    e.preventDefault();
    if (phoneSelected) {
      store.preview = true;
      render();
    } else paste();
    return;
  }
  if (commandOnly && e.code === "KeyC") {
    e.preventDefault();
    void realCopy();
    return;
  }
  if (commandOnly && e.code === "KeyP") {
    e.preventDefault();
    if (!phoneSelected) {
      store.pin();
      previewId = null;
      render();
    }
    return;
  }
  if (commandOnly && e.code === "KeyW") {
    e.preventDefault();
    closeTree();
    return;
  }
  if (commandOnly && /^Digit[1-9]$/.test(e.code)) {
    e.preventDefault();
    phoneSelected = false;
    const clip = store.results[Number(e.code.slice(-1)) - 1];
    if (clip) paste(clip);
    return;
  }
  const deletion = e.key === "Delete" || e.key === "Backspace";
  if (
    deletion &&
    !command &&
    !e.ctrlKey &&
    !e.altKey &&
    !e.shiftKey &&
    (keyboardCards || !store.query)
  ) {
    e.preventDefault();
    if (!e.repeat) deleteSelected();
    return;
  }
  if (!command && !e.ctrlKey && (e.key.length === 1 || deletion)) {
    keyboardCards = false;
    if (target !== search && e.key.length === 1 && !e.altKey) {
      e.preventDefault();
      focusSearch();
      search.setRangeText(
        e.key,
        search.selectionStart ?? search.value.length,
        search.selectionEnd ?? search.value.length,
        "end",
      );
      search.dispatchEvent(new Event("input"));
    }
  }
});
screen.addEventListener("pointerdown", (e) => {
  if (!store.visible || draggingCard) return;
  if ((e.target as Element).closest(".paper,#preview,.tree-controls,.menubar"))
    return;
  closeTree();
});
function clock() {
  $("#clock").textContent = new Date().toLocaleTimeString(locale, {
    hour: "2-digit",
    minute: "2-digit",
  });
}
clock();
setInterval(clock, 60000);
function renderStats() {
  renderDownload();
  if (!lastStats) return;
  const { stats, stale } = lastStats;
  for (const id of ["stars", "downloads"]) {
    $(`#${id} span`).textContent = stats
      ? new Intl.NumberFormat(locale, { notation: "compact" }).format(
          id === "stars" ? stats.stars : stats.downloads,
        )
      : t("暂不可用");
    $(`#${id}`).title = stats
      ? `${id === "stars" ? "GitHub Stars" : t("所有公开 Release 安装包累计下载")} · ${stale ? t("缓存数据") + " · " : ""}${new Date(stats.updatedAt).toLocaleString(locale)}`
      : t("GitHub 数据暂不可用");
  }
}
void loadStats(statsSnapshot).then((result) => {
  if (downloadRequested) return;
  lastStats = result;
  renderStats();
});
bindLabels($("#app"));
document.documentElement.lang = locale;
document.title = `PasteHistory — ${t("复制过的，随时找回。")}`;
document
  .querySelector('meta[name="description"]')
  ?.setAttribute("content", t("复制过的，随时找回。"));
displaySample();
render();
focusSearch();
