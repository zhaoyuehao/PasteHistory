import { createRenderer } from "./renderer.js";
// The shoreline distance map shares the photograph's cover transform with both the shader and navigation.
export async function ocean(canvas) {
  const load = (path) =>
    new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = new URL("assets/" + path, import.meta.url);
    });
  const [photo, shore, ripple] = await Promise.all(
    ["cove.webp", "shore.png", "ripples.png"].map(load),
  );
  const map = document.createElement("canvas");
  map.width = shore.width;
  map.height = shore.height;
  const ctx = map.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(shore, 0, 0);
  const pixels = ctx.getImageData(0, 0, map.width, map.height).data;
  let width = 0,
    height = 0,
    fw = 0,
    fh = 0,
    paint = () => {};
  const gl = canvas.getContext("webgl2", {
    alpha: false,
    antialias: true,
    depth: true,
  });
  async function initialize() {
    try {
      if (!gl) throw Error("WebGL 2 unavailable");
      const render = await createRenderer(gl, [photo, shore, ripple]);
      paint = (t, strength, sky, boats) =>
        render([width, height, fw, fh], t, strength, sky, boats);
      canvas.hidden = false;
    } catch (error) {
      console.warn("Sea renderer fallback:", error);
      canvas.hidden = true;
      paint = () => {};
    }
    canvas.getRootNode().host.classList.toggle("mesh-ready", !canvas.hidden);
  }
  await initialize();
  canvas.addEventListener("webglcontextlost", (event) => {
    event.preventDefault();
    canvas.hidden = true;
    paint = () => {};
    canvas.getRootNode().host.classList.remove("mesh-ready");
  });
  canvas.addEventListener("webglcontextrestored", initialize);
  return {
    resize(w, h) {
      width = w;
      height = h;
      fw = Math.max(w, (h * photo.width) / photo.height);
      fh = (fw * photo.height) / photo.width;
      const scale = Math.min(devicePixelRatio, 1.4, 2200 / Math.max(w, h));
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
    },
    depth(x, y) {
      const u = (x - width / 2) / fw + 0.5,
        v = (y - height / 2) / fh + 0.5;
      const col = Math.max(
        0,
        Math.min(map.width - 1, Math.floor(u * map.width)),
      );
      const row = Math.max(
        0,
        Math.min(map.height - 1, Math.floor(v * map.height)),
      );
      return pixels[(row * map.width + col) * 4] - 128;
    },
    paint(...args) {
      paint(...args);
    },
  };
}

export function precipitation(canvas, depth) {
  const ctx = canvas.getContext("2d");
  let drops = [],
    w = 0,
    h = 0,
    acc = 0;
  return {
    resize(width, height) {
      w = canvas.width = width;
      h = canvas.height = height;
      drops = [];
    },
    paint(dt, weather) {
      ctx.clearRect(0, 0, w, h);
      if (weather !== "rain" && weather !== "snow") {
        drops = [];
        return;
      }
      const snow = weather === "snow";
      acc += dt * Math.min(240, (w * h) / 4000);
      while (acc >= 1) {
        acc--;
        const x = Math.random() * w,
          y = Math.random() * h;
        if (depth(x, y) < 5) continue;
        drops.push({
          x,
          y,
          age: 0,
          size: 0.5 + Math.random(),
          flight: snow ? 1.7 : 0.36,
          snow,
        });
      }
      drops = drops.filter((p) => p.snow === snow && p.age < p.flight + 0.55);
      for (const p of drops) {
        p.age += dt;
        const left = p.flight - p.age;
        if (left > 0) {
          const x = p.x - left * (snow ? 10 : 52),
            y = p.y - left * (snow ? 30 : 235);
          ctx.beginPath();
          if (snow) {
            ctx.fillStyle = "#ffffffe0";
            ctx.arc(
              x + 2 * Math.sin(left * 4),
              y,
              1.9 * p.size,
              0,
              2 * Math.PI,
            );
            ctx.fill();
          } else {
            ctx.strokeStyle = "rgba(220,241,255,.7)";
            ctx.lineWidth = p.size;
            ctx.moveTo(x - 2 * p.size, y - 9 * p.size);
            ctx.lineTo(x, y);
            ctx.stroke();
          }
        } else {
          const age = -left;
          ctx.strokeStyle =
            "rgba(216,246,255," + (1 - age / 0.55) * (snow ? 0.2 : 0.65) + ")";
          ctx.lineWidth = 0.9;
          ctx.beginPath();
          ctx.ellipse(
            p.x,
            p.y,
            1 + age * 16 * p.size,
            1 + age * 7 * p.size,
            0,
            0,
            2 * Math.PI,
          );
          ctx.stroke();
        }
      }
    },
  };
}
