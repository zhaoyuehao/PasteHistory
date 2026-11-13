import { ocean, precipitation } from "./ocean.js";

const $ = (id) => document.getElementById(id);
const desk = $("desk"),
  fleet = $("fleet"),
  menu = $("popup"),
  sheet = $("sheet"),
  body = $("contents");
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
  b.goal = choosePoint(b);
}
function updateAppearance(b) {
  b.el.querySelector("img").src = "assets/" + kind(b.name) + ".png";
  b.el.querySelector(".name").textContent = b.name;
  b.el.setAttribute("aria-label", b.name);
}
function add(name, file = null) {
  const el = document.createElement("button");
  el.className = "boat";
  el.setAttribute("aria-pressed", "false");
  el.innerHTML =
    '<span class="hull"><img alt="" draggable="false"><i class="lamp"></i></span><span class="name"></span>';
  const b = {
    name,
    file,
    el,
    x: 0,
    y: 0,
    heading: Math.random() * 6.28,
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
    if (e.button !== 0) return;
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
  };
  el.onclick = (e) => {
    if (dragged || held) return;
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
  el.ondblclick = () => openFile(b);
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
    else b.goal = choosePoint(b);
  });
}
function steer(b, dt) {
  const g = b.goal;
  if (!g || Math.hypot(g.x - b.x, g.y - b.y) < 24) b.goal = choosePoint(b);
  let dx = b.goal.x - b.x,
    dy = b.goal.y - b.y,
    dist = Math.max(1, Math.hypot(dx, dy));
  dx = dx / dist;
  dy = dy / dist;
  for (const n of boats) {
    if (n === b) continue;
    const x = b.x - n.x,
      y = b.y - n.y,
      d = Math.hypot(x, y);
    if (d > 0 && d < 65) {
      dx += (x / d) * (1 - d / 65) * 3;
      dy += (y / d) * (1 - d / 65) * 3;
    }
  }
  if (!safe(b.x + dx * 32, b.y + dy * 32)) {
    const nearby = points.filter((p) => Math.hypot(b.x - p.x, b.y - p.y) < 100);
    const best = nearby.reduce(
      (a, p) => (!a || water?.depth(p.x, p.y) > water?.depth(a.x, a.y) ? p : a),
      null,
    );
    if (best) {
      dx = best.x - b.x;
      dy = best.y - b.y;
    }
    b.goal = choosePoint(b);
  }
  const target =
    Math.atan2(dy, dx) + 0.13 * Math.sin(animationTime * 0.47 + b.y * 0.015);
  const turn = Math.atan2(
    Math.sin(target - b.heading),
    Math.cos(target - b.heading),
  );
  b.heading += Math.sign(turn) * Math.min(Math.abs(turn), dt * 1.5);
  const speed =
    (weather === "wind" ? 17 : 11) *
    Math.min(
      3,
      1 + 0.35 * b.clicks.filter((t) => t > Date.now() - week).length,
    );
  const nx = b.x + Math.cos(b.heading) * dt * speed,
    ny = b.y + Math.sin(b.heading) * dt * speed;
  if (
    safe(nx, ny) &&
    boats.every(
      (n) =>
        n === b ||
        Math.hypot(nx - n.x, ny - n.y) >= 40 ||
        Math.hypot(nx - n.x, ny - n.y) > Math.hypot(b.x - n.x, b.y - n.y),
    )
  ) {
    b.x = nx;
    b.y = ny;
  }
}
function closeMenu() {
  menu.hidden = true;
}
function menuAt(x, y, items) {
  menu.replaceChildren();
  for (const [label, action] of items) {
    const el = document.createElement(action ? "button" : "small");
    el.textContent = label;
    if (action)
      el.onclick = () => {
        closeMenu();
        action();
      };
    menu.append(el);
  }
  menu.hidden = false;
  menu.style.left = Math.max(4, Math.min(x, W - menu.offsetWidth - 5)) + "px";
  menu.style.top = Math.max(4, Math.min(y, H - menu.offsetHeight - 5)) + "px";
  menu.querySelector("button")?.focus({ preventScroll: true });
}
function popup(id, items) {
  const r = $(id).getBoundingClientRect();
  menuAt(r.left, r.bottom + 4, items);
}
function fileMenu(b, x, y) {
  select(b);
  menuAt(x, y, [
    [b.name],
    ["打开", () => openFile(b)],
    ["重命名", () => rename(b)],
    ["从此海面移除", () => remove(b)],
  ]);
}
function dialog(title) {
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
function openFile(b) {
  select(b);
  dialog(b.name);
  const token = previewId;
  if (b.file) {
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
          if (previewId === token) line("无法读取文件");
        });
    } else line("文件大小：" + Math.ceil(f.size / 1024) + " KB");
  } else if (b.example === "海的桌面.jpg") {
    const img = document.createElement("img");
    img.src = "assets/cove.webp";
    img.alt = "海湾航拍图";
    body.append(img);
  } else if (b.example === "落叶信.txt")
    line("落叶信\n\n今天风小，船慢慢经过灯塔。", "pre");
  else if (b.example === "赛博软装铺.zip")
    line("赛博软装铺.zip　/　落叶信.txt");
  else line("竹叶河 · WAV 音频示例");
  action("重命名", () => rename(b));
}
function rename(b) {
  dialog("重命名");
  const input = document.createElement("input");
  input.value = b.name;
  input.setAttribute("aria-label", "文件名");
  body.append(input);
  function save() {
    const name = input.value.trim();
    if (
      !name ||
      name.includes("/") ||
      boats.some((n) => n !== b && n.name === name)
    ) {
      input.setCustomValidity("请输入一个不重复的有效文件名");
      input.reportValidity();
      return;
    }
    b.name = name;
    updateAppearance(b);
    sheet.close();
    b.el.focus();
  }
  input.oninput = () => input.setCustomValidity("");
  input.onkeydown = (e) => {
    if (e.key === "Enter") save();
  };
  action("保存", save);
  input.focus();
  input.setSelectionRange(
    0,
    b.name.lastIndexOf(".") > 0 ? b.name.lastIndexOf(".") : b.name.length,
  );
}
function remove(b) {
  select(null);
  b.el.remove();
  boats.splice(boats.indexOf(b), 1);
  tell("已从此海面移除 " + b.name);
}
function addFiles(files) {
  let count = 0;
  for (const f of files) {
    if (boats.length >= 40) break;
    add(f.name, f);
    count++;
  }
  tell(count ? "已添加 " + count + " 个文件" : "此海面最多容纳 40 个文件");
}
$("input").onchange = (e) => {
  addFiles(e.target.files);
  e.target.value = "";
};
$("picker").onclick = () => $("input").click();
$("files").onclick = () =>
  popup("files", [
    ["添加本地文件…", () => $("input").click()],
    ...(selected
      ? [
          ["打开", () => openFile(selected)],
          ["重命名", () => rename(selected)],
        ]
      : []),
    ["返回 PasteHistory", () => location.assign("../")],
  ]);
$("view").onclick = () =>
  popup("view", [
    [paused ? "恢复漂流" : "暂停漂流", () => (paused = !paused)],
    ["天气与昼夜", () => $("skies").click()],
  ]);
$("download").onclick = () => {
  dialog("下载海的桌面");
  line("海的桌面 · macOS");
  line("Mac 版尚未开放下载，敬请期待。");
  action("下载 Mac 版 · 敬请期待", () => {}).disabled = true;
};
$("close").onclick = () => sheet.close();
sheet.onclose = () => {
  previewId++;
  if (previewURL) {
    URL.revokeObjectURL(previewURL);
    previewURL = null;
  }
};
document.addEventListener("pointerdown", (e) => {
  if (!menu.contains(e.target)) closeMenu();
  if (e.target === desk) select(null);
});
desk.oncontextmenu = (e) => {
  if (e.target.closest(".boat,dialog,#popup")) return;
  e.preventDefault();
  menuAt(e.clientX, e.clientY, [
    ["添加本地文件…", () => $("input").click()],
    ["天气与昼夜", () => $("skies").click()],
  ]);
};
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    closeMenu();
    return;
  }
  if (sheet.open || !menu.hidden || e.target.matches("input,textarea")) return;
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
  $("clock").textContent = now.toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  $("condition").textContent =
    mode === "auto" && !sun ? "天气" : names[weather];
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
    status = label + " · " + names[natural] + " · Open-Meteo";
    followCoords = [lat, lon, label];
  } catch {
    if (request !== weatherRequest) return;
    status = "天气暂不可用 · 按本地时间";
  }
  updateSky();
}
function locate() {
  if (!navigator.geolocation) {
    tell("浏览器不支持定位");
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (p) => {
      mode = "auto";
      sky = "auto";
      sync(p.coords.latitude, p.coords.longitude, "当前位置");
    },
    () => tell("未取得位置，可在天气菜单手动体验"),
    { maximumAge: 600000, timeout: 10000 },
  );
}
$("skies").onclick = () =>
  popup("skies", [
    [status],
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
      (mode === key ? "✓ " : "") + label,
      () => {
        mode = key;
        updateSky();
      },
    ]),
    ["昼夜预览"],
    ...Object.entries({ auto: "当地时间", day: "白天", night: "夜晚" }).map(
      ([key, label]) => [
        (sky === key ? "✓ " : "") + label,
        () => {
          sky = key;
          updateSky();
        },
      ],
    ),
  ]);
function render(b) {
  b.el.style.transform =
    "translate(" + Math.round(b.x - 69) + "px," + Math.round(b.y - 23) + "px)";
  b.el.firstElementChild.style.transform = "rotate(" + b.heading + "rad)";
}
let previous = 0;
function frame(now) {
  requestAnimationFrame(frame);
  if (document.hidden || now - previous < (paused ? 250 : 30)) return;
  const dt = Math.min(0.075, (now - previous) / 1000);
  previous = now;
  if (!paused) animationTime += dt;
  water?.paint(animationTime, weather === "wind" ? 1.8 : 1);
  fx?.paint(paused ? 0 : dt, weather);
  for (const b of boats) {
    if (!paused && !b.hold && !(sheet.open && b === selected)) steer(b, dt);
    render(b);
  }
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
    const sites = await (await fetch("zones.json")).json();
    const p = sites[zone];
    if (p && !followCoords && !weatherRequest)
      sync(p[0], p[1], zone.split("/").pop() + "（按时区）");
  } catch {}
  setInterval(() => {
    if (!document.hidden && followCoords) sync(...followCoords);
  }, 30 * 60000);
  setTimeout(() => ($("hint").hidden = true), 12000);
}
init();
