export const REPO = "https://github.com/zhaoyuehao/PasteHistory";
const API = "https://api.github.com/repos/zhaoyuehao/PasteHistory";
export type Stats = {
  stars: number;
  downloads: number;
  version: string | null;
  downloadUrl: string | null;
  updatedAt: string;
};
type Release = {
  draft: boolean;
  tag_name: string;
  published_at: string;
  assets: {
    name: string;
    download_count: number;
    browser_download_url: string;
  }[];
};
export const isInstaller = (name: string) =>
  /^PasteHistory.*\.(zip|dmg|pkg)$/i.test(name);
export function aggregate(stars: number, releases: Release[]): Stats {
  const published = releases
    .filter((r) => !r.draft)
    .sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at));
  const latest = published.find((r) =>
    r.assets.some(
      (a) => isInstaller(a.name) && /arm64|apple.silicon/i.test(a.name),
    ),
  );
  const asset = latest?.assets.find(
    (a) => isInstaller(a.name) && /arm64|apple.silicon/i.test(a.name),
  );
  return {
    stars,
    downloads: published.reduce(
      (n, r) =>
        n +
        r.assets
          .filter((a) => isInstaller(a.name))
          .reduce((s, a) => s + a.download_count, 0),
      0,
    ),
    version: latest?.tag_name ?? null,
    downloadUrl: asset?.browser_download_url ?? null,
    updatedAt: new Date().toISOString(),
  };
}
export function validStats(x: unknown): x is Stats {
  if (!x || typeof x !== "object") return false;
  const s = x as Stats;
  return (
    Number.isFinite(s.stars) &&
    s.stars >= 0 &&
    Number.isFinite(s.downloads) &&
    s.downloads >= 0 &&
    Number.isFinite(Date.parse(s.updatedAt)) &&
    (s.version === null || typeof s.version === "string") &&
    (s.downloadUrl === null ||
      (typeof s.downloadUrl === "string" &&
        s.downloadUrl.startsWith(`${REPO}/releases/download/`)))
  );
}
export async function fetchStats(
  fetcher: typeof fetch = fetch,
): Promise<Stats> {
  async function get(url: string) {
    const r = await fetcher(url, {
      headers: { Accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new Error(`GitHub ${r.status}`);
    return r;
  }
  const repo = await (await get(API)).json();
  if (!Number.isFinite(repo.stargazers_count))
    throw new Error("Invalid repository");
  const releases: Release[] = [];
  let next: string | null = `${API}/releases?per_page=100`;
  while (next) {
    const response = await get(next);
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error("Invalid releases");
    releases.push(...page);
    next =
      response.headers.get("Link")?.match(/<([^>]+)>; rel="next"/)?.[1] ?? null;
    if (next && !next.startsWith(`${API}/releases?`))
      throw new Error("Unexpected pagination URL");
  }
  return aggregate(repo.stargazers_count, releases);
}
export async function loadStats(
  snapshotUrl: string,
): Promise<{ stats: Stats | null; stale: boolean }> {
  let cached: Stats | null = null;
  try {
    const x = JSON.parse(
      localStorage.getItem("pastehistory-github-v1") ?? "null",
    );
    if (validStats(x)) cached = x;
  } catch {
    /* Storage can be blocked. */
  }
  if (cached && Date.now() - Date.parse(cached.updatedAt) < 30 * 60 * 1000)
    return { stats: cached, stale: false };
  try {
    const stats = await fetchStats();
    try {
      localStorage.setItem("pastehistory-github-v1", JSON.stringify(stats));
    } catch {}
    return { stats, stale: false };
  } catch {
    if (cached) return { stats: cached, stale: true };
    try {
      const r = await fetch(snapshotUrl);
      const x = await r.json();
      if (validStats(x)) return { stats: x, stale: true };
    } catch {}
    return { stats: null, stale: true };
  }
}
