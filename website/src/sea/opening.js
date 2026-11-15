import { createOpeningWater } from "./openingWater.js";
import { createOpeningFiles } from "./openingFiles.js";

const seenKey = "sea.opening.seen";
const duration = 6.2;

function wasSeen() {
  try {
    return localStorage.getItem(seenKey) === "1";
  } catch {
    return false;
  }
}

// Starts with a still desktop while the ocean loads. The animation clock is
// advanced by the sea renderer and stops while the tab is in the background.
export function firstTide(desk, fleet, boats) {
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  if (motion.matches || location.hash === "#pastehistory" || wasSeen()) return null;

  const waterCanvas = document.createElement("canvas");
  const icons = document.createElement("div");
  waterCanvas.className = "opening-water";
  icons.className = "opening-icons";
  for (const el of [waterCanvas, icons]) el.setAttribute("aria-hidden", "true");
  fleet.before(waterCanvas, icons);
  const water = createOpeningWater(waterCanvas);
  const files = createOpeningFiles(icons, boats);
  const events = new AbortController();
  const options = { signal: events.signal };
  let elapsed = 0;
  let last = null;
  let finished = false;

  function finish() {
    if (finished) return;
    finished = true;
    events.abort();
    files.destroy();
    water.destroy();
    waterCanvas.remove();
    icons.remove();
    fleet.inert = false;
    try {
      localStorage.setItem(seenKey, "1");
    } catch {
      // The desktop remains usable when browser storage is disabled.
    }
  }

  fleet.inert = true;
  desk.addEventListener("pointerdown", finish, { ...options, capture: true });
  desk.addEventListener("contextmenu", finish, { ...options, capture: true });
  desk.addEventListener("dragenter", finish, options);
  document.addEventListener("keydown", finish, { ...options, capture: true });
  document.addEventListener("open-pastehistory", finish, options);
  window.addEventListener("hashchange", () => {
    if (location.hash === "#pastehistory") finish();
  }, options);
  motion.addEventListener("change", () => { if (motion.matches) finish(); }, options);
  document.addEventListener("visibilitychange", () => { last = null; }, options);

  function paint(now, width, height) {
    if (finished) return false;
    if (last !== null) elapsed += Math.max(0, (now - last) / 1000);
    last = now;
    if (elapsed >= duration) {
      finish();
      return false;
    }
    water.paint(elapsed, width, height);
    files.paint(elapsed, width, height);
    return true;
  }

  // Show wallpaper and files immediately; the first live frame starts the clock.
  water.paint(0, desk.clientWidth, desk.clientHeight);
  files.paint(0, desk.clientWidth, desk.clientHeight);
  return { paint };
}
