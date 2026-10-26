import "./style.css";
import "./native.css";
import { HistoryStore, type Clip } from "./store";
import {
  initialClips,
  sampleImage,
  sampleLanguages,
  type SampleLanguage,
} from "./fixtures";
import { TreeStage } from "./tree";
import { TreeEntrance } from "./entrance";
import { NativePreview } from "./preview";
import { PHONE_ID, dateLabel } from "./native";
import { loadStats, REPO } from "./github";
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
  reset: '<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7"/>',
  pin: '<path d="m8 3 8 0-1 6 4 4H5l4-4-1-6m4 10v9"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
};
const icon = (name: keyof typeof icons) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;
const lights = (name: string) =>
  `<div class="traffic"><button class="red" data-minimize="${name}" aria-label="关闭${name === "browser" ? "素材窗口" : "备忘录"}"></button><button class="yellow" data-minimize="${name}" aria-label="最小化${name === "browser" ? "素材窗口" : "备忘录"}"></button><button class="green" data-expand="${name}" aria-label="放大窗口"></button></div>`;
$("#app").innerHTML = `
<div class="desktop native-desktop exploring" data-mobile-view="tree">
 <div class="wallpaper" aria-hidden="true"></div>
 <header class="menubar"><button class="brand" id="menu-tree">${icon("tree")}<b>PasteHistory</b></button><button data-open="browser">复制样例</button><div class="menu-spacer"></div><span class="system-status" aria-hidden="true">⌁ &nbsp; ▰</span><time id="clock"></time></header>
 <main id="desktop-main">
  <section class="hero-heading"><p>PasteHistory</p><h1>复制过的，随时找回。</h1></section>
  <section id="tree-area" aria-label="许愿树剪贴板"><div id="tree-stage"></div><div id="empty" hidden>枝头暂时空了。<br><small>换个关键词，或复制一条新灵感。</small></div><p class="tree-hint">点一张纸签，试试看。</p><div class="tree-controls"><span class="search-cord"></span><div class="search-tag"><span class="search-hole"></span>${icon("search")}<input id="search" aria-label="搜索剪贴板" autocomplete="off" spellcheck="false"><span id="page-label"></span></div></div><div id="layout-controls" hidden><button id="layout-drag">移动</button><button data-size=".82">小</button><button data-size="1">标准</button><button data-size="1.14">大</button><button id="layout-done">完成</button></div></section>
  <section class="download-area" aria-label="下载 PasteHistory"><button id="download-button" class="download-button">${icon("download")} 下载 Mac 版</button><p>Apple Silicon · macOS 14+</p><small>预览版 · 未经 Apple 公证</small></section>
  <section id="browser" class="window browser-window minimized" inert aria-label="素材浏览器"><div class="titlebar" data-drag-window="browser">${lights("browser")}<span>${icon("compass")} 复制一点灵感</span></div><div class="browser-body"><h2>从这里，挂上枝头。</h2><div class="sample-tabs" role="tablist" aria-label="素材类型"><button role="tab" aria-selected="true" data-sample="text">文字</button><button role="tab" aria-selected="false" data-sample="image">图片</button><button role="tab" aria-selected="false" data-sample="file">文件</button></div><label class="sample-language">示例语言<select id="sample-language" aria-label="示例语言"></select></label><div id="sample-content"></div><button id="collect" class="collect-button">${icon("copy")} 复制到许愿树</button><button id="more-samples" class="text-link">载入更多示例</button><small>仅在本页演示，不读取系统剪贴板。</small></div></section>
  <section id="notes" class="window notes-window" aria-label="备忘录"><div class="titlebar"><div class="traffic" aria-hidden="true"><span class="red"></span><span class="yellow"></span><span class="green"></span></div><span>备忘录</span><button id="clear-note" aria-label="清空备忘录">${icon("trash")}</button></div><div class="notes-body"><div class="notes-date">今天 · 我的灵感</div><h2>备忘录</h2><p class="note-drop-hint">把文字、图片纸签拖到这里，也可以直接粘贴图片。</p><div id="note-editor" role="textbox" aria-label="备忘录内容" contenteditable="true" aria-multiline="true" data-placeholder="写点什么，或把纸签拖进来…"></div></div><footer><span id="note-status">粘贴目标 · 保留光标位置</span><span>仅本次体验</span></footer></section>
 </main>
 <footer class="site-footer"><a href="${REPO}" target="_blank" rel="noopener" class="github-link">${icon("github")} GitHub</a><a href="${REPO}" target="_blank" rel="noopener" class="repo-url">github.com/zhaoyuehao/PasteHistory</a><div class="stats"><a id="stars" href="${REPO}/stargazers" target="_blank" rel="noopener">Star <span>—</span></a><span id="downloads">下载次数 <span>—</span></span></div></footer>
 <nav class="experience-tools" aria-label="体验工具" inert><button data-open="browser" aria-label="打开素材浏览器">${icon("copy")}<span>复制样例</span></button><button data-open="notes" aria-label="打开备忘录">${icon("note")}<span>备忘录</span></button><button data-open="tree" title="⇧⌘V">${icon("tree")}<span>许愿树</span></button><button id="actions-button" aria-expanded="false">网页辅助操作</button><button id="reset" aria-label="重置演示">${icon("reset")}<span>重置</span></button></nav>
 <div id="action-menu" hidden><button id="previous">上一组 <kbd>Page Up</kbd></button><button id="next">下一组 <kbd>Page Down</kbd></button><button id="toggle-preview">预览 <kbd>Space / ⌘Y</kbd></button><button id="paste">粘贴到原输入位置 <kbd>↵</kbd></button><button id="real-copy">复制到系统 <kbd>⌘C</kbd></button><button id="pin">置顶 / 取消置顶 <kbd>⌘P</kbd></button><button id="delete">删除 <kbd>Delete</kbd></button><button id="clear-search">清空搜索</button><button id="layout-toggle">调整布局 <kbd>⇧⌘M</kbd></button><button id="zoom-in">放大预览 ＋</button><button id="zoom-out">缩小预览 −</button><button id="close-preview">关闭预览 <kbd>Esc</kbd></button><button id="close-tree">关闭许愿树 <kbd>⌘W</kbd></button></div>
 <div id="preview" class="preview" hidden aria-label="纸签预览"><div class="preview-compact"></div><div class="preview-face"><div class="preview-hole"></div><div class="preview-heading"><span id="preview-source"></span></div><div id="preview-content"></div><div id="preview-date"></div></div></div>
 <div id="toast" role="status" aria-live="polite"></div>
 <dialog id="info-dialog"><button class="dialog-close" aria-label="关闭说明">${icon("close")}</button><div id="info-content"></div></dialog>
</div>`;
let store = new HistoryStore(initialClips());

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
  const toolbar = $(".experience-tools").getBoundingClientRect();
  const width = rootLinks.offsetWidth;
  const x = Math.max(
    width / 2 + 12,
    Math.min(
      desktop.width - width / 2 - 12,
      tag.left + tag.width / 2 - desktop.left,
    ),
  );
  const y = Math.min(
    tag.bottom - desktop.top + 12,
    toolbar.top - desktop.top - rootLinks.offsetHeight - 8,
  );
  rootLinks.style.left = `${x}px`;
  rootLinks.style.top = `${Math.max(42, y)}px`;
}
new ResizeObserver(placeRootLinks).observe(rootLinks);
$(".hero-heading").remove();
$(".tree-hint").remove();
$(".experience-tools").inert = false;
const notesRail = document.createElement("aside");
notesRail.className = "notes-rail";
const shortcuts = document.createElement("section");
shortcuts.className = "shortcut-guide";
shortcuts.setAttribute("aria-label", "常用快捷键");
shortcuts.innerHTML = `<h2>随手试一试</h2><p>拖一张纸签到备忘录，文字和图片都能留下。</p><dl><div><dt>↑ / ↓</dt><dd>选择纸签</dd></div><div><dt>空格</dt><dd>展开 / 收起预览</dd></div><div><dt>↵</dt><dd>粘贴到输入位置</dd></div><div><dt>⌘P</dt><dd>置顶 / 取消置顶</dd></div><div><dt>Delete</dt><dd>删除选中的记录</dd></div><div><dt>⇧⌘V</dt><dd>唤起 / 收起许愿树</dd></div></dl><small>直接输入可搜索 · ⇧空格输入空格<br>Esc 逐层关闭 · 中文组词时优先交给输入法</small>`;
notesRail.append($("#notes"), shortcuts);
$(".desktop").append(notesRail);
let layoutScale = 1;
function enterExperience() {
  $(".desktop").classList.add("exploring");
  $(".tree-controls").inert = false;
  $(".experience-tools").inert = false;
}
let sampleKind: Clip["kind"] = "text";
let sampleLanguage: SampleLanguage = "zh-Hans";
const sampleDrafts = new Map<string, string>();
const languageSelect = $<HTMLSelectElement>("#sample-language");
for (const language of sampleLanguages) {
  const option = document.createElement("option");
  option.value = language.code;
  option.textContent = language.label;
  languageSelect.append(option);
}
languageSelect.onchange = () => {
  const editor = $<HTMLTextAreaElement>("#sample-text");
  if (editor) sampleDrafts.set(sampleLanguage, editor.value);
  sampleLanguage = languageSelect.value as SampleLanguage;
  displaySample();
};
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
let downloadUrl: string | null = null;
let latestVersion: string | null = null;
function placeNativeTree() {
  const stacked = screen.clientWidth < 900;
  const railWidth = stacked
    ? 0
    : Math.min(300, Math.max(250, screen.clientWidth * 0.24));
  notesRail.style.width = stacked ? "calc(100% - 32px)" : `${railWidth}px`;
  const availableWidth = screen.clientWidth - (stacked ? 0 : railWidth + 40);
  const availableHeight = Math.max(
    1,
    screen.clientHeight - 30 - (stacked ? 650 : 0),
  );
  const height = 920 * layoutScale;
  const width = 880 * layoutScale;
  const scale = Math.min(
    1,
    (availableWidth - 24) / width,
    availableHeight / height,
  );
  Object.assign($("#tree-area").style, {
    width: `${width}px`,
    height: `${height}px`,
    left: `${(availableWidth - width * scale) / 2}px`,
    top: `${30 + (availableHeight - height * scale) / 2}px`,
    transform: `scale(${scale})`,
    transformOrigin: "0 0",
  });
  notesRail.style.top = stacked ? `${availableHeight + 180}px` : "76px";
}

placeNativeTree();
window.addEventListener("resize", placeNativeTree);
const tree = new TreeStage($("#tree-stage"));
const note = $("#note-editor");
const search = $<HTMLInputElement>("#search");
const preview = $("#preview");
let previewId: string | null = null;
let previewSize = { width: 340, height: 210 };
let phoneSelected = false;
let layoutMode = false;
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
  resetTreePosition();
  render();
  focusSearch();
}
function closeTree() {
  store.preview = false;
  store.visible = false;
  if (layoutMode) setLayoutMode(false);
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
function resetTreePosition() {
  placeNativeTree();
}
function setLayoutMode(value: boolean) {
  layoutMode = value;
  tree.layoutEditing = value;
  store.preview = false;
  $("#layout-controls").hidden = !value;
  $(".desktop").classList.toggle("layout-editing", value);
  $(".tree-controls").inert = value;
  render();
  if (!value) focusSearch();
}
function togglePreview() {
  if (!store.selected && !phoneSelected) return;
  enterExperience();
  store.preview = !store.preview;
  focusSearch();
  render();
}
function toast(message: string) {
  $("#toast").textContent = message;
  $("#toast").classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 2600);
}
function displaySample() {
  const host = $("#sample-content");
  const language = sampleLanguages.find((l) => l.code === sampleLanguage)!;
  host.replaceChildren();
  if (sampleKind === "text") {
    const t = document.createElement("textarea");
    t.id = "sample-text";
    t.setAttribute("aria-label", "可复制的示例文字");
    t.value = sampleDrafts.get(sampleLanguage) ?? language.text;
    t.lang = sampleLanguage;
    t.oninput = () => sampleDrafts.set(sampleLanguage, t.value);
    host.append(t);
  } else if (sampleKind === "image") {
    const img = document.createElement("img");
    img.src = sampleImage;
    img.alt = language.image;
    host.append(img);
  } else {
    const p = document.createElement("div");
    p.className = "file-sample";
    p.textContent = `▤  ${language.file}`;
    p.lang = sampleLanguage;
    const small = document.createElement("small");
    small.textContent = `/Users/demo/Documents/${language.file} · 示例文件路径`;
    p.append(small);
    host.append(p);
  }
  document
    .querySelectorAll<HTMLButtonElement>("[data-sample]")
    .forEach((b) =>
      b.setAttribute("aria-selected", String(b.dataset.sample === sampleKind)),
    );
}
function syncInteraction() {
  const mobile = innerWidth < 800;
  const view = $(".desktop").dataset.mobileView;
  $(".download-area").inert = false;
  $("#tree-area").inert = !store.visible;
  for (const name of ["browser"]) {
    const window = $(`#${name}`);
    window.inert =
      window.classList.contains("minimized") || (mobile && view !== name);
  }
}
window.addEventListener("resize", syncInteraction);
function showWindow(name: string) {
  enterExperience();
  $(".desktop").dataset.mobileView = name;
  if (name === "tree") {
    presentTree();
  } else {
    if (store.visible) closeTree();
    const w = $(`#${name}`);
    w.classList.remove("minimized");
    if (name !== "notes") {
      w.classList.add("window-pop");
      setTimeout(() => w.classList.remove("window-pop"), 350);
    }
    syncInteraction();
    if (name === "notes") {
      pasteTarget = note;
      note.focus({ preventScroll: true });
      if (innerWidth < 900) {
        window.scrollTo({
          top: notesRail.getBoundingClientRect().top + scrollY - 16,
          behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
            ? "instant"
            : "smooth",
        });
      }
    }
  }
}
function collect() {
  const language = sampleLanguages.find((l) => l.code === sampleLanguage)!;
  const clip: Clip = {
    id: crypto.randomUUID(),
    kind: sampleKind,
    text:
      sampleKind === "text"
        ? $<HTMLTextAreaElement>("#sample-text").value
        : sampleKind === "image"
          ? language.image
          : language.file,
    lang: sampleLanguage,
    ...(sampleKind === "file"
      ? { paths: [`/Users/demo/Documents/${language.file}`] }
      : {}),
    source: sampleKind === "file" ? "访达" : "Safari",
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
  $("#browser").classList.add("minimized");
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
  $("#tree-area").classList.toggle("closed", !store.visible);
  $("#empty").hidden = store.results.length > 0;
  $("#page-label").textContent = store.results.length
    ? `${store.page + 1} / ${store.pages} · ${store.results.length}`
    : "0 / 0";
  $<HTMLButtonElement>("#previous").disabled =
    !store.visible || store.index <= 0;
  $<HTMLButtonElement>("#next").disabled =
    !store.visible || store.index >= store.results.length - 1;
  for (const id of ["pin", "delete", "paste", "real-copy"])
    $<HTMLButtonElement>(`#${id}`).disabled =
      !store.selected || phoneSelected || !store.visible;
  for (const id of [
    "toggle-preview",
    "layout-toggle",
    "clear-search",
    "close-tree",
  ])
    $<HTMLButtonElement>(`#${id}`).disabled = !store.visible;
  for (const id of ["zoom-in", "zoom-out", "close-preview"])
    $<HTMLButtonElement>(`#${id}`).disabled = !store.preview;
  $("#pin").setAttribute(
    "aria-pressed",
    String(store.selected?.pinned ?? false),
  );
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
  const want = !!(store.preview && id && store.visible && !layoutMode);
  const contentChanged = want && id !== previewId;
  if (contentChanged) {
    previewId = id;
    $("#preview-source").textContent = phoneSelected
      ? "手机同步"
      : `${String(store.index + 1).padStart(2, "0")}${clip?.pinned ? " · ↟" : ""} · ${clip?.source || "—"}`;
    $("#preview-date").textContent = clip
      ? dateLabel(clip.created)
      : "网页演示 · 未连接设备";
    const content = $("#preview-content");
    content.replaceChildren();
    content.lang = clip?.lang ?? "zh-Hans";
    content.classList.toggle("image-content", !!clip?.image);
    if (phoneSelected) {
      const p = document.createElement("p");
      p.textContent =
        "手机同步\n\nMac 版可以通过局域网与手机配对。网页体验不连接真实设备，也不生成配对二维码。";
      content.append(p);
    } else if (clip) {
      if (clip.image) {
        const img = document.createElement("img");
        img.src = clip.image;
        img.alt = clip.text;
        content.append(img);
        if (clip.ocr) {
          const label = document.createElement("small");
          label.textContent = "预置 OCR 示例文字";
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
            : "演示文件";
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
        text: file.name || "粘贴的图片",
        image,
        source: "本次粘贴",
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
          document.createTextNode(`[图片无法显示：${clip.text}]`),
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
  $("#note-status").textContent = clips.some((clip) => clip.image)
    ? "图片已放入备忘录"
    : "已粘贴到备忘录";
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
  toast("纸签已删除 · 可重置演示恢复");
}
function modal(html: string) {
  $("#info-content").innerHTML = html;
  $<HTMLDialogElement>("#info-dialog").showModal();
}
$("#download-button").onclick = () => {
  modal(
    `<span class="eyebrow">PASTEHISTORY FOR MAC</span><h2>给你的桌面，种一棵树。</h2><p>Apple Silicon · macOS 14 或更新版本</p><p class="release-warning">预览版，未经 Apple 公证。使用 Apple Development 签名，下载后可能受到 macOS 系统拦截。</p><p>解压后将 PasteHistory.app 放入「应用程序」。首次使用需在系统设置中允许辅助功能，才能粘贴到其他应用。</p><a id="release-link" class="primary-link" target="_blank" rel="noopener"></a><p class="muted" id="release-details"></p>`,
  );
  const link = $<HTMLAnchorElement>("#release-link");
  link.href = downloadUrl ?? `${REPO}/releases`;
  link.textContent = downloadUrl
    ? "下载 Apple Silicon 预览版 ↓"
    : "查看发布进度 ↗";
  $("#release-details").textContent =
    latestVersion ?? "安装包尚未发布。你现在就可以体验网页中的许愿树。";
};
$("#collect").onclick = collect;
$("#more-samples").onclick = () => {
  const ids = new Set(store.clips.map((c) => c.id));
  store.clips.push(...initialClips().filter((c) => !ids.has(c.id)));
  store.search("");
  search.value = "";
  showWindow("tree");
  $("#browser").classList.add("minimized");
  render();
  toast("已载入文字、图片与文件示例");
};
document.querySelectorAll<HTMLButtonElement>("[data-sample]").forEach(
  (b) =>
    (b.onclick = () => {
      sampleKind = b.dataset.sample as Clip["kind"];
      displaySample();
    }),
);
search.addEventListener("input", () => {
  if (composing) return;
  store.search(search.value);
  phoneSelected = false;
  keyboardCards = false;
  render();
});
search.addEventListener("focus", () => (keyboardCards = false));
search.addEventListener("pointerdown", () => (keyboardCards = false));
$("#clear-search").onclick = () => {
  search.value = "";
  store.search("");
  phoneSelected = false;
  render();
  search.focus();
};
$("#previous").onclick = () => {
  phoneSelected = false;
  focusSearch();
  keyboardCards = true;
  store.turn(-1);
  render();
};
$("#next").onclick = () => {
  phoneSelected = false;
  focusSearch();
  keyboardCards = true;
  store.turn(1);
  render();
};
$("#pin").onclick = () => {
  if (phoneSelected) return;
  store.pin();
  previewId = null;
  render();
};
$("#delete").onclick = deleteSelected;
$("#paste").onclick = () => paste();
$("#toggle-preview").onclick = togglePreview;
$("#real-copy").onclick = realCopy;
$("#close-preview").onclick = () => {
  store.preview = false;
  render();
};
$("#menu-tree").onclick = () => (store.visible ? closeTree() : presentTree());
$("#close-tree").onclick = closeTree;
$("#zoom-in").onclick = () => nativePreview.zoomBy(1.1);
$("#zoom-out").onclick = () => nativePreview.zoomBy(1 / 1.1);
$("#actions-button").onclick = () => {
  const menu = $("#action-menu");
  menu.hidden = !menu.hidden;
  $("#actions-button").setAttribute("aria-expanded", String(!menu.hidden));
};
$("#action-menu").addEventListener("click", (e) => {
  if ((e.target as Element).closest("button")) {
    $("#action-menu").hidden = true;
    $("#actions-button").setAttribute("aria-expanded", "false");
  }
});
$("#layout-toggle").onclick = () => setLayoutMode(!layoutMode);
$("#layout-done").onclick = () => setLayoutMode(false);
document.querySelectorAll<HTMLButtonElement>("[data-size]").forEach(
  (button) =>
    (button.onclick = () => {
      layoutScale = Number(button.dataset.size);
      $("#tree-area").style.setProperty("--layout-scale", String(layoutScale));
      resetTreePosition();
    }),
);
let layoutDrag: { x: number; y: number; left: number; top: number } | null =
  null;
$("#layout-drag").onpointerdown = (e) => {
  const r = $("#tree-area").getBoundingClientRect();
  const viewport = screen.getBoundingClientRect();
  layoutDrag = {
    x: e.clientX,
    y: e.clientY,
    left: r.left - viewport.left,
    top: r.top - viewport.top,
  };
  $("#layout-drag").setPointerCapture(e.pointerId);
};
$("#layout-drag").onpointermove = (e) => {
  if (!layoutDrag) return;
  const area = $("#tree-area");
  area.style.left = `${Math.max(0, Math.min(screen.clientWidth - area.offsetWidth, layoutDrag.left + e.clientX - layoutDrag.x))}px`;
  area.style.top = `${Math.max(30, Math.min(screen.clientHeight - area.offsetHeight, layoutDrag.top + e.clientY - layoutDrag.y))}px`;
  area.style.transform = "none";
  tree.wake();
};
$("#layout-drag").onpointerup = $("#layout-drag").onpointercancel = () => {
  layoutDrag = null;
};
$(".dialog-close").onclick = () => $<HTMLDialogElement>("#info-dialog").close();
$("#info-dialog").onclick = (e) => {
  if (e.target === $("#info-dialog"))
    $<HTMLDialogElement>("#info-dialog").close();
};
$("#clear-note").onclick = () => {
  clearNotes();
  $("#note-status").textContent = "粘贴目标 · 保留光标位置";
};
$("#reset").onclick = () => {
  store = new HistoryStore(initialClips());

  phoneSelected = false;
  setLayoutMode(false);
  layoutScale = 1;
  $("#tree-area").style.removeProperty("--layout-scale");
  resetTreePosition();
  $(".desktop").classList.add("exploring");
  $(".tree-controls").inert = false;
  $(".experience-tools").inert = false;
  search.value = "";
  clearNotes();
  pasteTarget = null;
  previewId = null;
  sampleKind = "text";
  sampleLanguage = "zh-Hans";
  languageSelect.value = sampleLanguage;
  sampleDrafts.clear();
  keyboardCards = false;
  $("#note-status").textContent = "粘贴目标 · 保留光标位置";
  displaySample();
  document.querySelectorAll<HTMLElement>(".window").forEach((w) => {
    w.classList.remove("expanded");
    if (w.id !== "notes") w.classList.add("minimized");
    w.style.removeProperty("left");
    w.style.removeProperty("top");
    w.style.removeProperty("right");
  });
  $(".desktop").dataset.mobileView = "tree";
  render();
  toast("已回到最初的桌面");
};
document
  .querySelectorAll<HTMLButtonElement>("[data-open]")
  .forEach((b) => (b.onclick = () => showWindow(b.dataset.open!)));
document.querySelectorAll<HTMLButtonElement>("[data-minimize]").forEach(
  (b) =>
    (b.onclick = () => {
      $(`#${b.dataset.minimize}`).classList.add("minimized");
      $(".desktop").dataset.mobileView = "tree";
      syncInteraction();
    }),
);
document
  .querySelectorAll<HTMLButtonElement>("[data-expand]")
  .forEach(
    (b) =>
      (b.onclick = () =>
        $(`#${b.dataset.expand}`).classList.toggle("expanded")),
  );
// Only title bars move windows. Content interaction remains native text selection.
document.querySelectorAll<HTMLElement>("[data-drag-window]").forEach((bar) => {
  let drag: { x: number; y: number; left: number; top: number } | null = null;
  const w = $(`#${bar.dataset.dragWindow}`);
  bar.onpointerdown = (e) => {
    if ((e.target as Element).closest("button") || innerWidth < 800) return;
    const r = w.getBoundingClientRect();
    drag = { x: e.clientX, y: e.clientY, left: r.left, top: r.top };
    bar.setPointerCapture(e.pointerId);
    w.classList.add("dragging");
  };
  bar.onpointermove = (e) => {
    if (!drag) return;
    w.style.left = `${Math.max(0, Math.min(innerWidth - w.offsetWidth, drag.left + e.clientX - drag.x))}px`;
    w.style.top = `${Math.max(42, Math.min(innerHeight - 130, drag.top + e.clientY - drag.y))}px`;
    w.style.right = "auto";
  };
  const end = () => {
    drag = null;
    w.classList.remove("dragging");
  };
  bar.onpointerup = end;
  bar.onpointercancel = end;
});
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
  if (
    draggingCard ||
    composing ||
    e.isComposing ||
    e.keyCode === 229 ||
    $<HTMLDialogElement>("#info-dialog").open
  )
    return;
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
  if (command && e.shiftKey && !e.ctrlKey && !e.altKey && e.code === "KeyM") {
    e.preventDefault();
    if (!e.repeat) setLayoutMode(!layoutMode);
    return;
  }
  if (layoutMode) {
    if (e.key === "Escape") {
      e.preventDefault();
      setLayoutMode(false);
    } else if (commandOnly && e.code === "KeyR") {
      e.preventDefault();
      layoutScale = 1;
      $("#tree-area").style.removeProperty("--layout-scale");
      resetTreePosition();
    }
    return;
  }
  if (
    target.closest(
      ".menubar,.experience-tools,#action-menu,.download-area,.site-footer,#browser,#notes",
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
  if (!store.visible || layoutMode || draggingCard) return;
  if (
    (e.target as Element).closest(
      ".paper,#preview,.tree-controls,#layout-controls,.menubar",
    )
  )
    return;
  closeTree();
});
function clock() {
  $("#clock").textContent = new Date().toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
  });
}
clock();
setInterval(clock, 60000);
void loadStats(`${import.meta.env.BASE_URL}github-stats.json`).then(
  ({ stats, stale }) => {
    for (const id of ["stars", "downloads"]) {
      $(`#${id} span`).textContent = stats
        ? new Intl.NumberFormat("zh-CN", { notation: "compact" }).format(
            id === "stars" ? stats.stars : stats.downloads,
          )
        : "暂不可用";
      $(`#${id}`).title = stats
        ? `${id === "stars" ? "GitHub Stars" : "所有公开 Release 安装包累计下载"} · ${stale ? "缓存数据 · " : ""}${new Date(stats.updatedAt).toLocaleString("zh-CN")}`
        : "GitHub 数据暂不可用";
    }
    downloadUrl = stats?.downloadUrl ?? null;
    latestVersion = stats?.version ?? null;
  },
);
displaySample();
render();
focusSearch();
