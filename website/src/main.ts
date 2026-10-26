import "./style.css";
import { HistoryStore, type Clip } from "./store";
import { initialClips, welcomeClips, sampleImage } from "./fixtures";
import { TreeStage } from "./tree";
import { Spring } from "./motion";
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
<div class="desktop" data-mobile-view="tree">
 <div class="wallpaper" aria-hidden="true"></div>
 <header class="menubar"><button class="brand" id="menu-tree">${icon("tree")}<b>PasteHistory</b></button><button data-open="browser">复制样例</button><button id="about-button">帮助</button><div class="menu-spacer"></div><span class="system-status" aria-hidden="true">⌁ &nbsp; ▰</span><time id="clock"></time></header>
 <main id="desktop-main">
  <section class="hero-heading"><p>PasteHistory</p><h1>复制过的，随时找回。</h1></section>
  <section id="tree-area" aria-label="许愿树剪贴板"><div id="tree-stage"></div><div id="empty" hidden>枝头暂时空了。<br><small>换个关键词，或复制一条新灵感。</small></div><p class="tree-hint">点一张纸签，试试看。</p><div class="tree-controls" inert><div class="search-wrap">${icon("search")}<input id="search" aria-label="搜索剪贴板" placeholder="搜索剪贴板历史…" autocomplete="off"><button id="clear-search" aria-label="清空搜索">×</button></div><div class="tree-toolbar"><button id="previous" aria-label="上一组">‹</button><span id="page-label"></span><button id="next" aria-label="下一组">›</button><span class="toolbar-divider"></span><button id="pin" title="置顶选中纸签" aria-label="置顶选中纸签">${icon("pin")}</button><button id="delete" title="删除选中纸签" aria-label="删除选中纸签">${icon("trash")}</button><button id="paste" class="paste-button">粘贴 ↵</button></div></div></section>
  <section class="download-area" aria-label="下载 PasteHistory"><button id="download-button" class="download-button">${icon("download")} 下载 Mac 版</button><p>Apple Silicon · macOS 14+</p><small>预览版 · 未经 Apple 公证</small></section>
  <section id="browser" class="window browser-window minimized" inert aria-label="素材浏览器"><div class="titlebar" data-drag-window="browser">${lights("browser")}<span>${icon("compass")} 复制一点灵感</span></div><div class="browser-body"><h2>从这里，挂上枝头。</h2><div class="sample-tabs" role="tablist" aria-label="素材类型"><button role="tab" aria-selected="true" data-sample="text">文字</button><button role="tab" aria-selected="false" data-sample="image">图片</button><button role="tab" aria-selected="false" data-sample="file">文件</button></div><div id="sample-content"></div><button id="collect" class="collect-button">${icon("copy")} 复制到许愿树</button><button id="more-samples" class="text-link">载入更多示例</button><small>仅在本页演示，不读取系统剪贴板。</small></div></section>
  <section id="notes" class="window notes-window minimized" inert aria-label="备忘录"><div class="titlebar" data-drag-window="notes">${lights("notes")}<span>备忘录</span><button id="clear-note" aria-label="清空备忘录">${icon("trash")}</button></div><div class="notes-body"><div class="notes-date">今天 · 我的灵感</div><h2>先记下来。</h2><div id="note-editor" role="textbox" aria-label="备忘录内容" contenteditable="true" aria-multiline="true" data-placeholder="在这里写点什么…&#10;也可以把纸签拖进来。"></div></div><footer><span id="note-status">准备接住你的灵感</span><span>仅本次体验</span></footer></section>
 </main>
 <footer class="site-footer"><a href="${REPO}" target="_blank" rel="noopener" class="github-link">${icon("github")} GitHub</a><a href="${REPO}" target="_blank" rel="noopener" class="repo-url">github.com/zhaoyuehao/PasteHistory</a><div class="stats"><a id="stars" href="${REPO}/stargazers" target="_blank" rel="noopener">Star <span>—</span></a><span id="downloads">下载次数 <span>—</span></span></div></footer>
 <nav class="experience-tools" aria-label="体验工具" inert><button data-open="browser" aria-label="打开素材浏览器">${icon("copy")}<span>复制样例</span></button><button data-open="notes" aria-label="打开备忘录">${icon("note")}<span>备忘录</span></button><button data-open="tree" aria-label="打开许愿树">${icon("tree")}<span>许愿树</span></button><button id="reset" aria-label="重置演示">${icon("reset")}<span>重置</span></button></nav>
 <div id="preview" class="preview" hidden aria-label="纸签预览"><div class="preview-hole"></div><div class="preview-heading"><span id="preview-source"></span><button id="close-preview" aria-label="关闭预览">${icon("close")}</button></div><div id="preview-content"></div><footer><button id="real-copy">${icon("copy")} 复制到系统</button><button id="preview-paste">粘贴到备忘录 ↵</button></footer></div>
 <div id="toast" role="status" aria-live="polite"></div>
 <dialog id="info-dialog"><button class="dialog-close" aria-label="关闭说明">${icon("close")}</button><div id="info-content"></div></dialog>
</div>`;
let store = new HistoryStore(welcomeClips());
store.selectedId = null;
let exploring = false;
function enterExperience() {
  exploring = true;
  $(".desktop").classList.add("exploring");
  $(".tree-controls").inert = false;
  $(".experience-tools").inert = false;
}
let sampleKind: Clip["kind"] = "text";
let composing = false;
let keyboardCards = false;
let noteRange: Range | null = null;
let toastTimer: ReturnType<typeof setTimeout>;
let downloadUrl: string | null = null;
let latestVersion: string | null = null;
const tree = new TreeStage($("#tree-stage"));
const note = $("#note-editor");
const search = $<HTMLInputElement>("#search");
const preview = $("#preview");
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
let previewId: string | null = null;
const openMotion = new Spring(0),
  px = new Spring(0),
  py = new Spring(0),
  previewScale = new Spring(1);
let previewFrame = 0,
  previewLast = 0;
let source = { x: 0, y: 0, width: 150 };
let previewWidth = 370;
function toast(message: string) {
  $("#toast").textContent = message;
  $("#toast").classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 2600);
}
function displaySample() {
  const host = $("#sample-content");
  host.replaceChildren();
  if (sampleKind === "text") {
    const t = document.createElement("textarea");
    t.id = "sample-text";
    t.setAttribute("aria-label", "可复制的示例文字");
    t.value = "慢一点，灵感会追上来。\n给生活留一点空白。";
    host.append(t);
  } else if (sampleKind === "image") {
    const img = document.createElement("img");
    img.src = sampleImage;
    img.alt = "布莱埃斯湖的湖水、木屋与山峰，Luca Bravo 摄影";
    host.append(img);
  } else {
    const p = document.createElement("div");
    p.className = "file-sample";
    p.textContent = "▤  秋日灵感.fig";
    const small = document.createElement("small");
    small.textContent = "设计灵感 / 秋日色板.fig · 示例文件路径";
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
  $(".download-area").inert = mobile && view !== "tree";
  $(".tree-hint").setAttribute("aria-hidden", String(exploring));
  $("#tree-area").inert = !store.visible || (mobile && view !== "tree");
  for (const name of ["browser", "notes"]) {
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
    store.visible = true;
    render();
  } else {
    const w = $(`#${name}`);
    w.classList.remove("minimized");
    w.classList.add("window-pop");
    setTimeout(() => w.classList.remove("window-pop"), 350);
    syncInteraction();
    if (name === "notes") note.focus();
  }
}
function collect() {
  const clip: Clip = {
    id: crypto.randomUUID(),
    kind: sampleKind,
    text:
      sampleKind === "text"
        ? $<HTMLTextAreaElement>("#sample-text").value
        : sampleKind === "image"
          ? "山野来信 · 布莱埃斯湖.jpg"
          : "设计灵感 / 秋日色板.fig",
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
    store.selectedId,
    store.preview || openMotion.value > 0,
    store.visible,
  );
  $("#tree-area").classList.toggle("closed", !store.visible);
  $("#empty").hidden = store.results.length > 0;
  $("#page-label").textContent =
    `${store.page + 1} / ${store.pages} · ${store.results.length} 张`;
  $<HTMLButtonElement>("#previous").disabled = store.page === 0;
  $<HTMLButtonElement>("#next").disabled = store.page === store.pages - 1;
  for (const id of ["pin", "delete", "paste"])
    $<HTMLButtonElement>(`#${id}`).disabled = !store.selected;
  $("#pin").setAttribute(
    "aria-pressed",
    String(store.selected?.pinned ?? false),
  );
  syncInteraction();
  updatePreview();
}
function select(id: string) {
  store.select(id, true);
  enterExperience();
  keyboardCards = true;
  render();
}
tree.onSelect = select;
tree.onDrag = (id) => {
  enterExperience();
  showWindow("notes");
  store.select(id);
  store.preview = false;
  keyboardCards = true;
  render();
};
function updatePreview() {
  const clip = store.selected;
  const want = !!(store.preview && clip && store.visible);
  openMotion.target = want ? 1 : 0;
  if (clip && (want || openMotion.value > 0)) {
    const rect = tree.rect(clip.id);
    if (rect) source = { x: rect.left, y: rect.top, width: rect.width };
    previewWidth = Math.min(370, innerWidth - 32);
    preview.style.width = `${previewWidth}px`;
    const tx = Math.max(
      16,
      Math.min(innerWidth - previewWidth - 16, source.x - 35),
    );
    const ty = Math.max(48, Math.min(innerHeight - 420, source.y - 60));
    if (preview.hidden) {
      px.value = source.x;
      py.value = source.y;
      previewScale.value = source.width / previewWidth;
      previewScale.velocity = 0;
      px.velocity = 0;
      py.velocity = 0;
    }
    px.target = want ? tx : source.x;
    py.target = want ? ty : source.y;
    previewScale.target = want ? 1 : source.width / previewWidth;
    if (previewId !== clip.id) {
      previewId = clip.id;
      $("#preview-source").textContent =
        `${clip.source} · ${clip.pinned ? "已置顶" : "刚刚的灵感"}`;
      const content = $("#preview-content");
      content.replaceChildren();
      if (clip.image) {
        const img = document.createElement("img");
        img.src = clip.image;
        img.alt = clip.text;
        content.append(img);
        const label = document.createElement("small");
        label.textContent = clip.ocr
          ? "预置 OCR 示例文字"
          : "真实摄影 · Luca Bravo · 布莱埃斯湖";
        content.append(label);
      }
      const p = document.createElement("p");
      p.textContent = clip.image ? (clip.ocr ?? clip.text) : clip.text;
      content.append(p);
      content.scrollTop = 0;
    }
  }
  if (want) {
    preview.hidden = false;
    preview.inert = false;
  } else preview.inert = true;
  wakePreview();
}
function wakePreview() {
  if (!previewFrame && !document.hidden) {
    previewLast = performance.now();
    previewFrame = requestAnimationFrame(animatePreview);
  }
}
function animatePreview(now: number) {
  previewFrame = 0;
  const dt = Math.min(0.04, (now - previewLast) / 1000);
  previewLast = now;
  for (const s of [openMotion, px, py, previewScale]) {
    if (reduced.matches) {
      s.value = s.target;
      s.velocity = 0;
    } else s.step(dt);
  }
  preview.style.transform = `translate(${px.value}px,${py.value}px) scale(${previewScale.value})`;
  preview.style.opacity = String(
    Math.max(0, Math.min(1, openMotion.value * 3)),
  );
  const settled = [openMotion, px, py, previewScale].every((s) => s.settled);
  if (openMotion.target === 0 && settled) {
    preview.hidden = true;
    previewId = null;
    tree.render(store.entries, store.selectedId, false, store.visible);
    return;
  }
  if (!settled) previewFrame = requestAnimationFrame(animatePreview);
}
document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    cancelAnimationFrame(previewFrame);
    previewFrame = 0;
  } else wakePreview();
});
tree.onLayout = () => updatePreview();
function rememberSelection() {
  const s = getSelection();
  if (s?.rangeCount && note.contains(s.anchorNode))
    noteRange = s.getRangeAt(0).cloneRange();
}
document.addEventListener("selectionchange", rememberSelection);
function paste(clip = store.selected) {
  if (!clip) return;
  showWindow("notes");
  let range: Range;
  if (noteRange && note.contains(noteRange.commonAncestorContainer)) {
    range = noteRange;
  } else {
    range = document.createRange();
    range.selectNodeContents(note);
    range.collapse(false);
  }
  range.deleteContents();
  const fragment = document.createDocumentFragment();
  if (clip.image) {
    const img = document.createElement("img");
    img.src = clip.image;
    img.alt = clip.text;
    img.className = "note-image";
    fragment.append(img);
  } else fragment.append(document.createTextNode(clip.text));
  const end = document.createTextNode("\n");
  fragment.append(end);
  range.insertNode(fragment);
  range.setStartAfter(end);
  range.collapse(true);
  const selection = getSelection();
  selection?.removeAllRanges();
  selection?.addRange(range);
  noteRange = range;
  note.focus();
  $("#note-status").textContent =
    "已粘贴 · " +
    new Date().toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
    });
  store.preview = false;
  render();
  toast("已粘贴到备忘录");
}
async function realCopy() {
  const clip = store.selected;
  if (!clip) return;
  try {
    await navigator.clipboard.writeText(clip.text);
    toast(clip.image ? "已复制图片标题" : "已复制到系统剪贴板");
  } catch {
    toast("浏览器未允许复制；仍可粘贴到演示备忘录");
  }
}
function deleteSelected() {
  if (!store.selected) return;
  store.remove();
  previewId = null;
  render();
  toast("纸签已删除 · 可重置演示恢复");
}
function modal(html: string) {
  $("#info-content").innerHTML = html;
  $<HTMLDialogElement>("#info-dialog").showModal();
}
function help() {
  modal(
    `<span class="eyebrow">A QUIETER PLACE FOR IDEAS</span><h2>一棵树，收好你的灵感。</h2><p>这是浏览器中的可操作演示。文字、图片与文件路径均为示例，你输入的内容只保留在当前页面中。</p><dl><dt>打开许愿树</dt><dd>菜单栏图标 / 许愿树按钮 / ⇧⌘V</dd><dt>选择与预览</dt><dd>↑ ↓ 选择 · 单击或空格展开</dd><dt>粘贴与整理</dt><dd>回车粘贴 · Delete 删除 · 按钮置顶</dd><dt>翻组</dt><dd>Page Up / Page Down 或树下方箭头</dd><dt>关闭</dt><dd>Esc 先关闭预览，再收起许愿树</dd></dl><p class="muted">浏览器占用的快捷键请使用按钮。macOS App 另支持本地 Vision OCR、iCloud 和局域网手机同步；本网页不连接这些服务。</p><a href="${REPO}" target="_blank" rel="noopener" class="dialog-link">查看 GitHub 与完整说明 ↗</a>`,
  );
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
  keyboardCards = false;
  render();
});
search.addEventListener("focus", () => (keyboardCards = false));
search.addEventListener("pointerdown", () => (keyboardCards = false));
$("#clear-search").onclick = () => {
  search.value = "";
  store.search("");
  render();
  search.focus();
};
$("#previous").onclick = () => {
  store.turn(-1);
  render();
};
$("#next").onclick = () => {
  store.turn(1);
  render();
};
$("#pin").onclick = () => {
  store.pin();
  previewId = null;
  render();
};
$("#delete").onclick = deleteSelected;
$("#paste").onclick = () => paste();
$("#preview-paste").onclick = () => paste();
$("#real-copy").onclick = realCopy;
$("#close-preview").onclick = () => {
  store.preview = false;
  render();
};
$("#menu-tree").onclick = () => {
  enterExperience();
  store.visible = !store.visible;
  if (!store.visible) store.preview = false;
  $(".desktop").dataset.mobileView = "tree";
  render();
};
$("#about-button").onclick = help;
$(".dialog-close").onclick = () => $<HTMLDialogElement>("#info-dialog").close();
$("#info-dialog").onclick = (e) => {
  if (e.target === $("#info-dialog"))
    $<HTMLDialogElement>("#info-dialog").close();
};
$("#clear-note").onclick = () => {
  note.replaceChildren();
  noteRange = null;
  $("#note-status").textContent = "准备接住你的灵感";
};
$("#reset").onclick = () => {
  store = new HistoryStore(welcomeClips());
  store.selectedId = null;
  exploring = false;
  $(".desktop").classList.remove("exploring");
  $(".tree-controls").inert = true;
  $(".experience-tools").inert = true;
  search.value = "";
  note.replaceChildren();
  noteRange = null;
  previewId = null;
  sampleKind = "text";
  keyboardCards = false;
  $("#note-status").textContent = "准备接住你的灵感";
  displaySample();
  document.querySelectorAll<HTMLElement>(".window").forEach((w) => {
    w.classList.remove("expanded");
    w.classList.add("minimized");
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
note.addEventListener("dragover", (e) => {
  e.preventDefault();
  if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
  $("#notes").classList.add("drop-ready");
});
note.addEventListener("dragleave", () =>
  $("#notes").classList.remove("drop-ready"),
);
note.addEventListener("drop", (e) => {
  e.preventDefault();
  $("#notes").classList.remove("drop-ready");
  const id = e.dataTransfer?.getData("application/x-pastehistory");
  const clip = store.clips.find((c) => c.id === id);
  if (clip) paste(clip);
});
// Accept external pastes as plain text, never imported HTML.
note.addEventListener("paste", (e) => {
  e.preventDefault();
  const text = e.clipboardData?.getData("text/plain");
  if (text)
    paste({
      id: "external",
      kind: "text",
      text,
      source: "粘贴",
      created: Date.now(),
      pinned: false,
    });
});
document.addEventListener("compositionstart", () => (composing = true));
document.addEventListener("compositionend", () => {
  composing = false;
  if (document.activeElement === search) {
    store.search(search.value);
    render();
  }
});
document.addEventListener("keydown", (e) => {
  if (composing || e.isComposing || $<HTMLDialogElement>("#info-dialog").open)
    return;
  const target = e.target as HTMLElement;
  const editing =
    target.isContentEditable ||
    target instanceof HTMLTextAreaElement ||
    (target instanceof HTMLInputElement && target !== search);
  if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.code === "KeyV" && !editing) {
    e.preventDefault();
    store.visible = !store.visible;
    store.preview = false;
    render();
    return;
  }
  if (editing || !store.visible) return;
  const cardTarget =
    target === document.body || target === search || !!target.closest(".paper");
  if (e.key === "Escape") {
    e.preventDefault();
    if (store.preview) store.preview = false;
    else store.visible = false;
    render();
    return;
  }
  if (e.metaKey || e.ctrlKey || e.altKey || !cardTarget) return;
  if (
    ["ArrowDown", "ArrowUp", "PageDown", "PageUp", "Enter", " "].includes(e.key)
  )
    enterExperience();
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    keyboardCards = true;
    store.move(e.key === "ArrowDown" ? 1 : -1);
    render();
  } else if (e.key === "PageDown" || e.key === "PageUp") {
    e.preventDefault();
    keyboardCards = true;
    store.turn(e.key === "PageDown" ? 1 : -1);
    render();
  } else if (
    e.key === "Enter" &&
    (target !== search || keyboardCards || !search.value)
  ) {
    e.preventDefault();
    paste();
  } else if (
    e.key === " " &&
    !e.shiftKey &&
    (target !== search || keyboardCards)
  ) {
    e.preventDefault();
    store.preview = !store.preview;
    render();
  } else if (
    (e.key === "Delete" || e.key === "Backspace") &&
    !e.repeat &&
    (keyboardCards || target !== search)
  ) {
    e.preventDefault();
    deleteSelected();
  }
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
