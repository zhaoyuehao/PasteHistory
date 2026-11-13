import {
  t,
  locale,
  bindLanguageSelect,
  onLanguageChange,
  bindLabels,
} from "../i18n";
import { asset } from "./assets.js";
import seaStyles from "./sea.css?inline";
import { finderMenu } from "./menu.js";
import { advance } from "./navigation.js";
import { ocean, precipitation } from "./ocean.js";

import { modelPose } from "./waves.js";
import { markup } from "./desktop.js";
const root = document
  .getElementById("sea-desktop")
  .attachShadow({ mode: "open" });
root.innerHTML = markup;
const css = document.createElement("style");
css.textContent = seaStyles;
root.prepend(css);
const $ = (id) => root.getElementById(id);

const desk = $("desk"),
  fleet = $("fleet"),
  menu = $("popup"),
  sheet = $("sheet"),
  body = $("contents");
desk.style.setProperty(
  "--coast-photo",
  'url("' + asset("assets/cove.webp") + '")',
);
bindLabels(desk);
bindLanguageSelect($("sea-language"));
onLanguageChange(() => {
  closeMenu();
  updateSky();
});
function format(key, values) {
  return t(key).replace(/\{(\w+)\}/g, (_, name) => values[name]);
}
const { open: menuAt, close: closeMenu } = finderMenu(root, desk, menu);
let copied = null,
  editing = null;
const trash = [];
const boats = [],
  week = 7 * 86400000;
const examples = ["赛博软装铺.zip", "海的桌面.jpg", "落叶信.txt", "竹叶河.wav"];
const media = /^(png|jpg|jpeg|heic|webp|gif|mov|mp4)$/i;
function kind(name) {
  const ext = name.split(".").pop();
  if (media.test(ext)) return "cruiser";
  if (/^(zip|gz|tar|dmg|pkg|7z)$/i.test(ext)) return "freighter";
  if (/^(mp3|wav|m4a|aiff)$/i.test(ext)) return "launch";
  return "sloop";
}
let W = innerWidth,
  H = innerHeight,
  selected = null,
  paused = matchMedia("(prefers-reduced-motion: reduce)").matches;
let water = null,
  fx = null,
  points = [],
  mode = "auto",
  weather = "clear",
  natural = "clear",
  sun = null,
  light = 1;
let sky = "auto",
  status = "按本地时间",
  noticeTimer,
  previewURL,
  previewId = 0,
  animationTime = 0;
function tell(text) {
  $("status").textContent = text;
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => ($("status").textContent = ""), 2800);
}
function select(b) {
  selected?.el.setAttribute("aria-pressed", "false");
  selected = b;
  b?.el.setAttribute("aria-pressed", "true");
}
function safe(x, y) {
  return (
    x > 45 &&
    x < W - 45 &&
    y > 74 &&
    y < H - 98 &&
    (!water ||
      water.depth(x, y) > Math.min(64, (30 * 1586) / Math.max(W, H * 1.6)))
  );
}
function choosePoint(b) {
  const options = points.filter(
    (p) => !b || Math.hypot(p.x - b.x, p.y - b.y) > Math.min(W, H) * 0.24,
  );
  const pool = options.length ? options : points;
  return (
    pool[Math.floor(Math.random() * pool.length)] || { x: W * 0.52, y: H * 0.5 }
  );
}
function place(b, index) {
  const anchors = [
    [0.55, 0.39],
    [0.72, 0.56],
    [0.38, 0.65],
    [0.56, 0.76],
  ];
  const [u, v] = anchors[index % 4];
  const target = index < 4 ? { x: u * W, y: v * H } : choosePoint();
  const p = points.reduce(
    (best, next) =>
      Math.hypot(next.x - target.x, next.y - target.y) <
      Math.hypot(best.x - target.x, best.y - target.y)
        ? next
        : best,
    points[0] || target,
  );
  b.x = p.x;
  b.y = p.y;
  b.path = null;
}
function updateAppearance(b) {
  b.kind = b.folder ? "freighter" : kind(b.name);
  // The filename FNV seed, modulo four, as used by DesktopItem.
  b.variant = new TextEncoder()
    .encode(b.name)
    .reduce((n, c) => ((n ^ c) * 3) & 3, 1);
  b.el.querySelector("img").src = asset("assets/" + b.kind + ".png");
  b.el.querySelector(".name").textContent = b.name;
  b.el.setAttribute("aria-label", b.name);
}
function add(name, file = null, folder = false) {
  const el = document.createElement("button");
  el.className = "boat";
  el.setAttribute("aria-pressed", "false");
  el.innerHTML =
    '<span class="hull"><img alt="" draggable="false"><i class="lamp"></i></span><span class="name"></span>';
  const b = {
    name,
    file,
    folder,
    created: Date.now(),
    el,
    x: 0,
    y: 0,
    heading: Math.random() * 6.28,
    phase: Math.random() * 2 * Math.PI,
    cruise: 4.3 + Math.random() * 1.8,
    clicks: [],
    hold: false,
    example: file ? null : name,
  };
  if (b.example)
    try {
      b.clicks = JSON.parse(
        localStorage.getItem("sea.clicks." + b.example) || "[]",
      ).filter((t) => Number.isFinite(t) && t > Date.now() - week);
    } catch {}
  boats.push(b);
  fleet.append(el);
  place(b, boats.length - 1);
  updateAppearance(b);
  let down,
    timer,
    dragged = false,
    held = false;
  el.onpointerdown = (e) => {
    if (e.button !== 0 || e.ctrlKey || editing === b) return;
    select(b);
    closeMenu();
    b.hold = true;
    dragged = false;
    held = false;
    down = [e.clientX, e.clientY, b.x, b.y];
    el.setPointerCapture(e.pointerId);
    if (e.pointerType !== "mouse")
      timer = setTimeout(() => {
        held = true;
        fileMenu(b, e.clientX, e.clientY);
      }, 550);
  };
  el.onpointermove = (e) => {
    if (!down || held) return;
    const dx = e.clientX - down[0],
      dy = e.clientY - down[1];
    if (Math.hypot(dx, dy) > 5) {
      dragged = true;
      clearTimeout(timer);
    }
    if (dragged && safe(down[2] + dx, down[3] + dy)) {
      b.x = down[2] + dx;
      b.y = down[3] + dy;
    }
  };
  el.onpointerup = el.onpointercancel = () => {
    clearTimeout(timer);
    down = null;
    b.hold = false;
    if (dragged) b.path = null;
  };
  el.onclick = (e) => {
    if (dragged || held || editing === b || e.ctrlKey) return;
    select(b);
    b.clicks = b.clicks.filter((t) => t > Date.now() - week).slice(-30);
    b.clicks.push(Date.now());
    if (b.example)
      try {
        localStorage.setItem(
          "sea.clicks." + b.example,
          JSON.stringify(b.clicks),
        );
      } catch {}
    if (e.detail === 0 || matchMedia("(pointer: coarse)").matches) openFile(b);
  };
  el.ondblclick = () => {
    if (editing !== b) openFile(b);
  };
  el.oncontextmenu = (e) => {
    e.preventDefault();
    fileMenu(b, e.clientX, e.clientY);
  };
  return b;
}
function resize() {
  W = desk.clientWidth;
  H = desk.clientHeight;
  water?.resize(W, H);
  fx?.resize(W, H);
  points = [];
  for (let y = 75; y < H - 96; y += Math.max(16, H / 32))
    for (let x = 46; x < W - 44; x += Math.max(16, W / 44))
      if (safe(x, y)) points.push({ x, y });
  boats.forEach((b, i) => {
    if (!safe(b.x, b.y)) place(b, i);
    else b.path = null;
  });
}
function popup(id, items) {
  const button = $(id),
    r = button.getBoundingClientRect();
  menuAt(r.left, r.bottom + 3, items, button, button.textContent);
}
function unique(filename, folder = false, copy = false) {
  const i = folder ? -1 : filename.lastIndexOf("."),
    ext = i > 0 ? filename.slice(i) : "",
    base = i > 0 ? filename.slice(0, i) : filename;
  const stem = copy ? format("{n} 副本", { n: base }) : base;
  let n = 1,
    name = stem + ext;
  while (boats.some((b) => b.name === name)) name = stem + " " + ++n + ext;
  return name;
}
function room() {
  if (boats.length < 40) return true;
  tell(t("此海面最多容纳 40 个项目"));
  return false;
}
function duplicate(b) {
  if (!room()) return;
  const name = unique(
    b.name,
    b.folder,
    boats.some((item) => item.name === b.name),
  );
  const copy = add(name, b.file, b.folder);
  copy.example = b.example;
  select(copy);
  copy.el.focus();
}
function info(b) {
  const name = b?.name ?? t("桌面");
  dialog(format("{name}简介", { name }));
  line(format("名称：{n}", { n: name }));
  const type =
    !b || b.folder
      ? t("文件夹")
      : b.name.includes(".")
        ? format("{n} 文件", { n: b.name.split(".").pop().toUpperCase() })
        : t("文稿");
  line(format("种类：{n}", { n: type }));
  if (!b || b.folder)
    line(
      format("包含：{n}", {
        n: format("{n} 个项目", { n: b ? 0 : boats.length }),
      }),
    );
  if (b?.file)
    line(format("大小：{n} 字节", { n: b.file.size.toLocaleString(locale) }));
  if (b) line(t("位置：桌面"));
}
function fileMenu(b, x, y) {
  if (editing === b) return;
  select(b);
  menuAt(
    x,
    y,
    [
      ["打开", () => openFile(b)],
      null,
      ["移到废纸篓", () => remove(b)],
      null,
      ["显示简介", () => info(b)],
      ["重新命名", () => rename(b)],
      [locale === "zh-Hans" ? "复制" : t("制作副本"), () => duplicate(b)],
      [format("快速查看“{name}”", { name: b.name }), () => openFile(b, true)],
      null,
      [format("拷贝“{name}”", { name: b.name }), () => (copied = b)],
    ],
    b.el,
    "文件快捷菜单",
  );
}
function arrange(key) {
  const order = [...boats];
  if (key === "名称")
    order.sort((a, b) =>
      a.name.localeCompare(b.name, locale, { numeric: true }),
    );
  if (key === "种类")
    order.sort(
      (a, b) =>
        a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name, locale),
    );
  if (key === "添加日期") order.sort((a, b) => b.created - a.created);
  if (!key) order.sort((a, b) => b.x - a.x || a.y - b.y);
  const slots = [];
  for (let x = W - 75; x >= 45; x -= 142)
    for (let y = 86; y < H - 63; y += 90) if (safe(x, y)) slots.push({ x, y });
  order.forEach((b, i) => {
    if (slots[i]) {
      Object.assign(b, slots[i]);
      b.path = null;
      b.vx = b.vy = 0;
    }
  });
}
function viewOptions() {
  dialog(t("桌面"));
  const label = document.createElement("label");
  label.textContent = t("文字大小") + "　";
  const sizes = document.createElement("select");
  for (const n of [11, 12, 13, 14, 16, 18])
    sizes.add(new Option(format("{n} 点", { n }), String(n)));
  sizes.value = desk.dataset.textSize ?? "13";
  sizes.onchange = () => {
    desk.dataset.textSize = sizes.value;
    desk.style.setProperty("--file-label-size", sizes.value + "px");
  };
  label.append(sizes);
  body.append(label);
}
function desktopMenu(x, y) {
  select(null);
  menuAt(
    x,
    y,
    [
      [
        "新建文件夹",
        () => {
          if (!room()) return;
          const b = add(unique(t("未命名文件夹"), true), null, true);
          if (safe(x, y)) {
            b.x = x;
            b.y = y;
          }
          rename(b);
        },
      ],
      ...(copied ? [["粘贴项目", () => duplicate(copied)]] : []),
      null,
      ["显示简介", () => info(null)],
      null,
      ["整理", () => arrange(null)],
      [
        "整理方式",
        ["名称", "种类", "添加日期"].map((k) => [k, () => arrange(k)]),
      ],
      null,
      ["查看显示选项", viewOptions],
    ],
    desk,
    "桌面快捷菜单",
  );
}
function dialog(title) {
  sheet.removeAttribute("data-quick-look");
  previewId++;
  if (previewURL) {
    URL.revokeObjectURL(previewURL);
    previewURL = null;
  }
  closeMenu();
  body.replaceChildren();
  $("heading").textContent = title;
  if (!sheet.open) sheet.showModal();
}
function line(text, tag = "p") {
  const el = document.createElement(tag);
  el.textContent = text;
  body.append(el);
  return el;
}
function action(label, run) {
  const el = line(label, "button");
  el.onclick = run;
  return el;
}
function openFile(b, quickLook = false) {
  select(b);
  dialog(b.name);
  sheet.toggleAttribute("data-quick-look", quickLook);
  const token = previewId;
  if (b.folder) {
    line(format("{n} 个项目", { n: 0 }));
  } else if (b.file) {
    const f = b.file;
    if (/^(image|audio|video)\//.test(f.type)) {
      const el = document.createElement(
        f.type.startsWith("image") ? "img" : f.type.split("/")[0],
      );
      el.alt = b.name;
      el.controls = true;
      previewURL = URL.createObjectURL(f);
      el.src = previewURL;
      body.append(el);
    } else if (
      f.type.startsWith("text/") ||
      /\.(txt|md|csv|json)$/i.test(f.name)
    ) {
      f.slice(0, 32768)
        .text()
        .then((t) => {
          if (previewId === token) line(t, "pre");
        })
        .catch(() => {
          if (previewId === token) line(t("无法读取文件"));
        });
    } else line(format("文件大小：{n} KB", { n: Math.ceil(f.size / 1024) }));
  } else if (b.example === "海的桌面.jpg") {
    const img = document.createElement("img");
    img.src = asset("assets/cove.webp");
    img.alt = t("海湾航拍图");
    body.append(img);
  } else if (b.example === "落叶信.txt")
    line("落叶信\n\n" + t("今天风小，船慢慢经过灯塔。"), "pre");
  else if (b.example === "赛博软装铺.zip")
    line("赛博软装铺.zip　/　落叶信.txt");
  else line(t("竹叶河 · WAV 音频示例"));
  if (!quickLook) action(t("重新命名"), () => rename(b));
}
function rename(b) {
  if (sheet.open) sheet.close();
  select(b);
  editing = b;
  b.hold = true;
  const input = document.createElement("input"),
    label = b.el.querySelector(".name");
  input.className = "rename-field";
  input.setAttribute("aria-label", t("文件名"));
  input.value = b.name;
  // Keep the editor outside the button so Return cannot also open the file.
  modelPose(b, H, animationTime, 0, 1);
  render(b);
  const r = label.getBoundingClientRect();
  desk.append(input);
  const width = Math.min(W - 12, Math.max(160, r.width + 32));
  input.style.width = width + "px";
  input.style.left =
    Math.max(6, Math.min(W - width - 6, r.x + (r.width - width) / 2)) + "px";
  input.style.top = r.top + "px";
  label.hidden = true;
  function finish(save, explicit) {
    if (editing !== b) return;
    const name = input.value.trim();
    if (
      save &&
      (!name ||
        name.includes("/") ||
        boats.some((n) => n !== b && n.name === name))
    ) {
      if (explicit) {
        input.setCustomValidity(t("请输入未使用的有效文件名"));
        input.reportValidity();
        return;
      }
      save = false;
    }
    editing = null;
    b.hold = false;
    input.remove();
    label.hidden = false;
    if (save) {
      b.name = name;
      updateAppearance(b);
    }
    if (explicit) b.el.focus({ preventScroll: true });
  }
  input.onblur = () => finish(true, false);
  input.oninput = () => input.setCustomValidity("");
  input.onkeydown = (e) => {
    if (!e.isComposing && ["Enter", "Escape"].includes(e.key)) {
      e.preventDefault();
      e.stopPropagation();
      finish(e.key === "Enter", true);
    }
  };
  input.focus();
  input.setSelectionRange(
    0,
    !b.folder && b.name.lastIndexOf(".") > 0
      ? b.name.lastIndexOf(".")
      : b.name.length,
  );
}
function remove(b) {
  select(null);
  b.el.remove();
  boats.splice(boats.indexOf(b), 1);
  trash.push(b);
  desk.focus();
}
function undoTrash() {
  if (!trash.length || !room()) return;
  const b = trash.pop();
  b.name = unique(b.name, b.folder);
  boats.push(b);
  fleet.append(b.el);
  updateAppearance(b);
  b.path = null;
  select(b);
  b.el.focus();
}
function addFiles(files) {
  let count = 0;
  for (const f of files) {
    if (boats.length >= 40) break;
    add(unique(f.name), f);
    count++;
  }
  tell(
    count
      ? format("已添加 {n} 个文件", { n: count })
      : t("此海面最多容纳 40 个项目"),
  );
}
$("input").onchange = (e) => {
  addFiles(e.target.files);
  e.target.value = "";
};

$("files").onclick = () =>
  popup("files", [
    ...(trash.length ? [["撤销移到废纸篓", undoTrash]] : []),
    ["添加本地文件…", () => $("input").click()],
    ...(selected
      ? [
          ["打开", () => openFile(selected)],
          ["重新命名", () => rename(selected)],
        ]
      : []),
  ]);
$("view").onclick = () =>
  popup("view", [
    [paused ? "恢复漂流" : "暂停漂流", () => (paused = !paused)],
    ["天气与昼夜", () => $("skies").click()],
  ]);
$("product").onclick = () =>
  popup("product", [
    [
      "关于海的桌面",
      () => {
        dialog(t("关于海的桌面"));
        line(t("海的桌面"));
        line("赛博软装铺");
      },
    ],
    null,
    ["下载 Mac 版 · 敬请期待", download],
  ]);
function download() {
  dialog(t("下载海的桌面"));
  line(t("海的桌面") + " · macOS");
  line(t("Mac 版尚未开放下载，敬请期待。"));
  action(t("下载 Mac 版 · 敬请期待"), () => {}).disabled = true;
}
$("close").onclick = () => sheet.close();
sheet.onclose = () => {
  sheet.removeAttribute("data-quick-look");
  previewId++;
  if (previewURL) {
    URL.revokeObjectURL(previewURL);
    previewURL = null;
  }
};
root.addEventListener("pointerdown", (e) => {
  if (e.target === desk) select(null);
});
desk.oncontextmenu = (e) => {
  if (e.target.closest(".panel")) {
    e.preventDefault();
    return;
  }
  if (e.target.closest(".boat,dialog,header,input")) return;
  e.preventDefault();
  desktopMenu(e.clientX, e.clientY);
};
root.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    closeMenu();
    return;
  }
  if (
    sheet.open &&
    sheet.hasAttribute("data-quick-look") &&
    e.code === "Space" &&
    !e.repeat &&
    !e.target.closest("audio,video")
  ) {
    e.preventDefault();
    sheet.close();
    return;
  }
  if (sheet.open || !menu.hidden || e.target.matches("input,textarea")) return;
  if (e.isComposing || editing) return;
  if (e.key === "ContextMenu" || (e.shiftKey && e.key === "F10")) {
    e.preventDefault();
    if (selected) {
      const r = selected.el.getBoundingClientRect();
      fileMenu(selected, r.left + r.width / 2, r.top + r.height / 2);
    } else desktopMenu(W / 2, H / 2);
    return;
  }
  if (e.metaKey) {
    if (e.key === "Backspace" && selected) {
      e.preventDefault();
      remove(selected);
    } else if (e.key === "z" && trash.length) {
      e.preventDefault();
      undoTrash();
    } else if (e.key === "d" && selected) {
      e.preventDefault();
      duplicate(selected);
    } else if (e.key === "i") {
      e.preventDefault();
      info(selected);
    } else if (e.key === "c" && selected) {
      e.preventDefault();
      copied = selected;
    } else if (e.key === "v" && copied) {
      e.preventDefault();
      duplicate(copied);
    }
    return;
  }
  if (e.code === "Space" && selected) {
    e.preventDefault();
    if (!e.repeat) openFile(selected, true);
    return;
  }
  if (
    selected &&
    e.key === "Enter" &&
    (e.target === selected.el ||
      e.target === desk ||
      e.target === document.body)
  ) {
    e.preventDefault();
    rename(selected);
  }
});
desk.ondragover = (e) => {
  if (e.dataTransfer.types.includes("Files")) {
    e.preventDefault();
    desk.classList.add("over");
  }
};
desk.ondragleave = (e) => {
  if (!desk.contains(e.relatedTarget)) desk.classList.remove("over");
};
desk.ondrop = (e) => {
  e.preventDefault();
  desk.classList.remove("over");
  addFiles(e.dataTransfer.files);
};
const names = {
  clear: "晴天",
  rain: "下雨",
  snow: "下雪",
  wind: "大风",
  cloud: "多云",
};
let climate = [1, 0, 0.08, 0];
function updateSky() {
  const now = new Date();
  let day;
  if (sun && now > sun.start && now < sun.end)
    day = now > sun.rise && now < sun.set;
  else day = now.getHours() >= 6 && now.getHours() < 18;
  const night = sky === "night" || (sky === "auto" && !day);
  weather = mode === "auto" ? natural : mode;
  light =
    (night ? 0.33 : 1) *
    (weather === "rain"
      ? 0.77
      : weather === "snow"
        ? 0.87
        : weather === "cloud"
          ? 0.91
          : 1);
  desk.style.setProperty("--light", light);
  desk.style.setProperty("--lamp", night ? 1 : 0);
  desk.style.setProperty(
    "--saturation",
    weather === "rain" || night ? 0.75 : 1,
  );
  climate = [
    night ? 0 : 1,
    0,
    { rain: 0.98, snow: 0.87, cloud: 0.73 }[weather] ?? 0.08,
    0,
  ];
  $("clock").textContent = now.toLocaleTimeString(locale, {
    hour: "2-digit",
    minute: "2-digit",
  });
  $("condition").textContent = t(
    mode === "auto" && !sun ? "天气" : names[weather],
  );
}
let followCoords = null,
  weatherRequest = 0;
async function sync(lat, lon, label) {
  const request = ++weatherRequest;
  try {
    const q = new URLSearchParams({
      latitude: lat.toFixed(2),
      longitude: lon.toFixed(2),
      current: "weather_code,wind_speed_10m,precipitation",
      daily: "sunrise,sunset",
      timezone: "auto",
      timeformat: "unixtime",
      forecast_days: "1",
    });
    const res = await fetch("https://api.open-meteo.com/v1/forecast?" + q, {
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) throw Error();
    const data = await res.json();
    if (request !== weatherRequest) return;
    const c = data.current,
      code = c.weather_code;
    natural = [71, 73, 75, 77, 85, 86].includes(code)
      ? "snow"
      : code >= 51
        ? "rain"
        : c.wind_speed_10m >= 30
          ? "wind"
          : code >= 2
            ? "cloud"
            : "clear";
    const start = data.daily.time[0] * 1000;
    sun = {
      start,
      end: start + 86400000,
      rise: data.daily.sunrise[0] * 1000,
      set: data.daily.sunset[0] * 1000,
    };
    status = "loaded";
    followCoords = [lat, lon, label];
  } catch {
    if (request !== weatherRequest) return;
    status = "天气暂不可用 · 按本地时间";
  }
  updateSky();
}
function locate() {
  if (!navigator.geolocation) {
    tell(t("浏览器不支持定位"));
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (p) => {
      mode = "auto";
      sky = "auto";
      sync(p.coords.latitude, p.coords.longitude, null);
    },
    () => tell(t("未取得位置，可在天气菜单手动体验")),
    { maximumAge: 600000, timeout: 10000 },
  );
}
$("skies").onclick = () =>
  popup("skies", [
    [
      status === "loaded"
        ? [
            followCoords[2]
              ? format("{n}（按时区）", { n: followCoords[2] })
              : t("当前位置"),
            t(names[natural]),
            "Open-Meteo",
          ].join(" · ")
        : t(status),
    ],
    [
      "同步当地天气与昼夜",
      () => {
        mode = "auto";
        sky = "auto";
        updateSky();
        if (followCoords) sync(...followCoords);
        else locate();
      },
    ],
    ["使用当前位置…", locate],
    ["天气预览"],
    ...Object.entries(names).map(([key, label]) => [
      (mode === key ? "✓ " : "") + t(label),
      () => {
        mode = key;
        updateSky();
      },
    ]),
    ["昼夜预览"],
    ...Object.entries({ auto: "当地时间", day: "白天", night: "夜晚" }).map(
      ([key, label]) => [
        (sky === key ? "✓ " : "") + t(label),
        () => {
          sky = key;
          updateSky();
        },
      ],
    ),
  ]);
function render(b) {
  b.el.style.transform =
    "translate(" +
    Math.round(b.pose[0] - 69) +
    "px," +
    Math.round(H - b.pose[1] - 23) +
    "px)";
  b.el.firstElementChild.style.transform = "rotate(" + -b.pose[2] + "rad)";
}
let previous = 0;
function frame(now) {
  requestAnimationFrame(frame);
  if (document.hidden || now - previous < (paused ? 250 : 30)) return;
  const dt = Math.min(0.075, (now - previous) / 1000);
  previous = now;
  if (!paused) animationTime += dt;
  const strength = weather === "wind" ? 1.63 : weather === "rain" ? 1.3 : 0.85;
  fx?.paint(paused ? 0 : dt, weather);
  if (!paused)
    advance(
      boats,
      { points, w: W, h: H, safe },
      dt,
      animationTime,
      strength,
      sheet.open || !menu.hidden ? selected : null,
    );
  for (const b of boats) {
    if (b === editing) continue;
    modelPose(b, H, animationTime, paused ? 0 : dt, strength);
    render(b);
  }
  water?.paint(animationTime, strength, climate, boats);
}
async function init() {
  try {
    water = await ocean($("water"));
  } catch {
    $("water").hidden = true;
  }
  fx = precipitation($("rain"), (x, y) => water?.depth(x, y) ?? 100);
  resize();
  examples.forEach((n) => add(n));
  window.addEventListener("resize", resize);
  updateSky();
  requestAnimationFrame(frame);
  setInterval(updateSky, 30000);
  try {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const sites = await (await fetch(asset("zones.json"))).json();
    const p = sites[zone];
    if (p && !followCoords && !weatherRequest)
      sync(p[0], p[1], zone.split("/").pop());
  } catch {}
  setInterval(() => {
    if (!document.hidden && followCoords) sync(...followCoords);
  }, 30 * 60000);
}
$("clipboard").onclick = () =>
  document.dispatchEvent(new Event("open-pastehistory"));
init();
