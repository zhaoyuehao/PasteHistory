import { asset } from "./assets.js";
import { openingContact } from "./openingWater.js";
import fileStyles from "./openingFiles.css?inline";

function eased(value) {
  const t = Math.max(0, Math.min(1, value));
  return t * t * (3 - 2 * t);
}

const illustrations = {
  freighter: `<path fill="#767a7d" d="M18 4h5v23h-5z"/>
    <path d="M18.5 6h2m0 3h2m-4 3h2m0 3h2m-4 3h2m0 3h2" stroke="#eee8d7" stroke-width="1.8"/>
    <path fill="#676d71" stroke="#454c51" stroke-width=".7" fill-rule="evenodd"
      d="M19 24h3l2 8q0 2-2 2h-3q-2 0-2-2zm1 5-1 3h3l-1-3z"/>
    <path d="M14 39h19" stroke="#9ea8ac" stroke-width="1.5"/> `,
  sloop: `<path d="M14 21h15m-15 4h21m-21 4h21m-21 4h18m-18 4h12"
      fill="none" stroke="#708494" stroke-width="1.4" stroke-linecap="round"/>`,
  launch: `<path fill="#63639c" d="M21 22v11.5c-.9-.3-2-.2-3.1.2-2.3.8-3.8 2.9-3.3 4.6.6 1.8 3 2.3 5.3 1.5 1.9-.7 3.1-2 3.1-3.8V25.4l8.4-1.9v7.9c-.9-.2-1.9-.1-2.9.3-2.2.8-3.7 2.8-3.1 4.5s2.9 2.3 5.2 1.5c1.9-.7 3-2.1 3-3.7V18.9z"/>`,
};

const paperOutline = "M11 3.5h17L39 14.7v28.8a2.5 2.5 0 0 1-2.5 2.5h-25A2.5 2.5 0 0 1 9 43.5V6a2.5 2.5 0 0 1 2-2.5Z";

function fileGlyph(kind) {
  const holder = document.createElement("div");
  holder.className = "opening-file-glyph";
  if (kind === "cruiser") {
    const photo = document.createElement("img");
    photo.className = "opening-file-photo";
    photo.src = asset("assets/cove.webp");
    photo.alt = "";
    photo.draggable = false;
    holder.append(photo);
  } else {
    // One paper shape for the document types, with their familiar Finder-style marks.
    holder.innerHTML = `<svg viewBox="0 0 48 48" aria-hidden="true">
      <path fill="#f7f8f7" stroke="#a3abb0" stroke-width=".8" d="${paperOutline}"/>
      <path fill="#dae0e3" stroke="#afb9bf" stroke-width=".65" d="M28 3.8v9.5q0 1.5 1.5 1.5h9z"/>
      ${illustrations[kind] ?? illustrations.sloop}
    </svg>`;
  }
  return holder;
}

// The two columns use desktop icon spacing, with enough room for the live labels.
function desktopSlot(index, width, height) {
  const right = Math.min(width - 70, width * 0.8);
  const spacing = Math.min(205, Math.max(110, width * 0.18), width * 0.4);
  const top = Math.min(110, Math.max(76, height * 0.135));
  const rowHeight = Math.min(164, Math.max(72, height * 0.185));
  return {
    x: right - (index % 2 === 0 ? spacing : 0),
    y: top + Math.floor(index / 2) * rowHeight,
  };
}

export function createOpeningFiles(layer, boats) {
  const style = document.createElement("style");
  style.textContent = fileStyles;
  layer.append(style);
  layer.setAttribute("aria-hidden", "true");
  const crestImage = `url("${asset("assets/opening-foam.webp")}")`;
  const files = boats.map((boat) => {
    const glyph = fileGlyph(boat.kind);
    const crest = document.createElement("div");
    crest.className = "opening-file-crest";
    crest.style.backgroundImage = crestImage;
    layer.append(glyph, crest);
    const hull = boat.el.querySelector(".hull");
    boat.introOpacity = 0;
    hull.style.opacity = "0";
    return { boat, glyph, hull, crest };
  });

  return {
    paint(seconds, width, height) {
      if (!width || !height) return;
      for (const [index, { boat, glyph, hull, crest }] of files.entries()) {
        const start = desktopSlot(index, width, height);
        const age = seconds - openingContact(start.x / width, start.y / height);
        const drift = eased(age / 2.05);
        const reveal = eased((age - 1.53) / 0.56);
        const sway = Math.sin(Math.PI * drift);
        // modelPose has just evaluated the real route and the current wave displacement.
        const pose = (boat.pose ??= [boat.x, height - boat.y, -boat.heading, 0]);
        const x = start.x + (pose[0] - start.x) * drift + 6 * sway;
        const y = start.y + (height - pose[1] - start.y) * drift;
        pose[0] = x;
        pose[1] = height - y;
        boat.introOpacity = reveal;
        hull.style.opacity = String(reveal);
        glyph.style.opacity = String(1 - reveal);
        glyph.style.transform = `translate(${x}px,${y}px) translate(-50%,-50%) rotate(${(index % 2 ? -9 : 9) * sway}deg) scale(${1 - 0.2 * reveal},${1 - 0.56 * reveal})`;
        // A small section of the same swash passes over the file as it resolves into a hull.
        const foam = eased((age - 1.53) / 0.15) * (1 - eased((age - 1.91) / 0.19));
        crest.hidden = foam === 0;
        if (foam > 0) {
          const frame = (Math.floor((age - 1.53) * 19) + index * 5) % 24;
          const sweep = eased((age - 1.53) / 0.57);
          const size = Math.min(46, Math.max(36, Math.min(width, height) * 0.0625));
          crest.style.backgroundPosition = `${(frame % 4) * 100 / 3}% ${Math.floor(frame / 4) * 20}%`;
          crest.style.opacity = String(foam * 0.85);
          crest.style.transform = `translate(${x}px,${y + (sweep - 0.5) * size}px) translate(-50%,-50%) rotate(${index % 2 ? -4 : 4}deg)`;
        }
      }
    },
    destroy() {
      for (const { boat, glyph, hull, crest } of files) {
        delete boat.introOpacity;
        hull.style.removeProperty("opacity");
        glyph.remove();
        crest.remove();
      }
      style.remove();
    },
  };
}
