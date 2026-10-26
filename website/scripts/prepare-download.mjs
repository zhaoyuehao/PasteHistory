// Downloads the latest arm64 installer from GitHub Releases into
// public/downloads/ so the deployed site can serve it as a local direct link
// (mainland-friendly deploy: GitHub release links are unreachable there).
// Sets VITE_DOWNLOAD_URL / VITE_DOWNLOAD_VERSION and runs the production
// build with a root-relative base. Cloudflare / GitHub Pages builds never run
// this script, so they keep pointing at GitHub Releases.
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const API = "https://api.github.com/repos/zhaoyuehao/PasteHistory";
const OUT_DIR = new URL("../public/downloads/", import.meta.url);
const HEADERS = {
  Accept: "application/vnd.github+json",
  "User-Agent": "PasteHistory-website-build",
};
const isInstaller = (name) => /^PasteHistory.*\.(zip|dmg|pkg)$/i.test(name);
const isArm64 = (name) => /arm64|apple.silicon/i.test(name);

async function getJSON(url) {
  const r = await fetch(url, { headers: HEADERS });
  if (!r.ok) throw new Error(`GitHub ${r.status} for ${url}`);
  return r.json();
}

async function getBytes(url) {
  const r = await fetch(url, { headers: HEADERS });
  if (!r.ok) throw new Error(`Download ${r.status} for ${url}`);
  return new Uint8Array(await r.arrayBuffer());
}

const releases = await getJSON(`${API}/releases?per_page=100`);
const release = releases.find(
  (r) =>
    !r.draft &&
    r.assets.some((a) => isInstaller(a.name) && isArm64(a.name)),
);
if (!release) throw new Error("No published release with an arm64 installer");
const asset = release.assets.find(
  (a) => isInstaller(a.name) && isArm64(a.name),
);
const sumsAsset = release.assets.find((a) => /^SHA256SUMS\.txt$/i.test(a.name));

const bytes = await getBytes(asset.browser_download_url);
let sumsText = null;
if (sumsAsset) {
  sumsText = new TextDecoder().decode(await getBytes(sumsAsset.browser_download_url));
  const expected = new Map(
    sumsText
      .trim()
      .split("\n")
      .map((line) => {
        const [hash, name] = line.trim().split(/\s+/, 2);
        return [name, hash];
      }),
  );
  const hash = expected.get(asset.name);
  const actual = createHash("sha256").update(bytes).digest("hex");
  if (!hash) throw new Error(`No SHA256 entry for ${asset.name}`);
  if (hash !== actual)
    throw new Error(
      `SHA256 mismatch for ${asset.name}: expected ${hash}, got ${actual}`,
    );
}

await mkdir(OUT_DIR, { recursive: true });
await writeFile(new URL(asset.name, OUT_DIR), bytes);
if (sumsText)
  await writeFile(new URL("SHA256SUMS.txt", OUT_DIR), Buffer.from(sumsText, "utf8"));
console.log(
  `Bundled installer: downloads/${asset.name} (${release.tag_name}, ${bytes.length} bytes)`,
);

const viteBin = new URL("../node_modules/vite/bin/vite.js", import.meta.url);
const build = spawnSync(
  process.execPath,
  [fileURLToPath(viteBin), "build", "--base", "/"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      VITE_DOWNLOAD_URL: `downloads/${asset.name}`,
      VITE_DOWNLOAD_VERSION: release.tag_name,
    },
  },
);
process.exit(build.status ?? 1);
