import Foundation

/// 手机端网页：单文件内嵌 HTML。剪贴板历史以密文传输，
/// 页面内用 WebCrypto（HKDF 派生 AES-256-GCM，与 Mac 端同参数）解密显示。
enum WebSyncPage {
    static let html = #"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#1c1c1e">
<title>剪贴板</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
body { font-family: -apple-system, "PingFang SC", sans-serif; background: #1c1c1e; color: #f2f2f7;
       padding-bottom: env(safe-area-inset-bottom); }
header { position: sticky; top: 0; z-index: 10; background: rgba(28,28,30,.92); backdrop-filter: blur(12px);
         padding: max(env(safe-area-inset-top), 10px) 14px 10px; border-bottom: 1px solid #38383a; }
h1 { font-size: 17px; font-weight: 700; }
#status { font-size: 11px; color: #98989f; margin-top: 2px; }
.row { display: flex; gap: 8px; margin-top: 10px; }
input[type=search] { flex: 1; background: #2c2c2e; border: none; border-radius: 10px; color: #f2f2f7;
                     padding: 9px 12px; font-size: 16px; outline: none; }
#syncBtn { background: #0a84ff; color: #fff; border: none; border-radius: 10px; padding: 9px 14px;
           font-size: 15px; font-weight: 600; white-space: nowrap; }
#syncBtn:active { opacity: .7; }
#syncBtn.on { background: #30d158; }
main { padding: 10px 14px; }
.clip { background: #2c2c2e; border-radius: 12px; padding: 11px 13px; margin-bottom: 8px; }
.clip .content { font-size: 14.5px; line-height: 1.45; word-break: break-all; display: -webkit-box;
                 -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
.clip .meta { display: flex; gap: 8px; margin-top: 6px; font-size: 11px; color: #98989f; align-items: center; }
.badge { background: #3a3a3c; border-radius: 5px; padding: 1px 6px; font-size: 10px; }
.badge.pin { color: #ff9f0a; }
.thumb { width: 42px; height: 42px; border-radius: 7px; object-fit: cover; float: right; margin-left: 8px; }
#empty { text-align: center; color: #98989f; padding: 60px 20px; font-size: 14px; }
#overlay { position: fixed; inset: 0; background: rgba(0,0,0,.55); display: none; z-index: 20;
           padding: 20px; align-items: center; justify-content: center; }
#sheet { background: #2c2c2e; border-radius: 16px; width: 100%; max-width: 500px; max-height: 80vh;
         display: flex; flex-direction: column; overflow: hidden; }
#sheetHead { display: flex; justify-content: space-between; align-items: center; padding: 12px 16px;
             border-bottom: 1px solid #38383a; }
#sheetTitle { font-size: 12px; color: #98989f; }
#copyBtn { background: #0a84ff; color: #fff; border: none; border-radius: 9px; padding: 7px 16px;
           font-size: 15px; font-weight: 600; }
#detail { padding: 14px 16px; overflow-y: auto; font-size: 15px; line-height: 1.5; word-break: break-all;
          white-space: pre-wrap; }
#detail img { max-width: 100%; border-radius: 8px; margin: 8px 0; }
#toast { position: fixed; left: 50%; transform: translateX(-50%); bottom: 80px; background: #3a3a3c;
         color: #fff; padding: 10px 18px; border-radius: 12px; font-size: 14px; opacity: 0;
         transition: opacity .25s; pointer-events: none; z-index: 30; max-width: 85vw; text-align: center; }
#lock { position: fixed; inset: 0; background: #1c1c1e; z-index: 40; display: none;
        flex-direction: column; align-items: center; justify-content: center; gap: 14px; padding: 30px; }
#lock input { background: #2c2c2e; border: 1px solid #48484a; border-radius: 10px; color: #fff;
              padding: 12px 14px; font-size: 22px; text-align: center; width: 180px; letter-spacing: 8px; }
#lock button { background: #0a84ff; color: #fff; border: none; border-radius: 10px; padding: 11px 0;
               width: 180px; font-size: 16px; font-weight: 600; }
#lock p { color: #98989f; font-size: 13px; text-align: center; line-height: 1.6; }
</style>
</head>
<body>
<header>
  <h1>剪贴板历史</h1>
  <div id="status">连接中…</div>
  <div class="row">
    <input type="search" id="q" placeholder="搜索（含图片内文字）">
    <button id="syncBtn" onclick="syncClipboard()">同步剪贴板</button>
  </div>
</header>
<main id="list"><div id="empty">加载中…</div></main>

<div id="overlay" onclick="if(event.target===this)closeSheet()">
  <div id="sheet">
    <div id="sheetHead"><span id="sheetTitle"></span><button id="copyBtn" onclick="copyCurrent()">复制</button></div>
    <div id="detail"></div>
  </div>
</div>
<div id="toast"></div>
<div id="lock">
  <p>请输入 Mac 端显示的 6 位配对码<br>（重新扫码即可自动填入）</p>
  <input id="pairInput" inputmode="numeric" maxlength="6" placeholder="······">
  <button onclick="submitPair()">解锁</button>
</div>

<script>
const $ = id => document.getElementById(id);
let key = null, token = null, clips = [], current = null;

// ---- 配对码：URL fragment 优先，其次 localStorage ----
async function initPair() {
  const m = location.hash.match(/pair=(\d{6})/);
  if (m) { localStorage.setItem('phPair', m[1]); history.replaceState(null,'','/'); }
  let code = localStorage.getItem('phPair');
  if (!code) { $('lock').style.display = 'flex'; return false; }
  return await unlock(code);
}
async function submitPair() {
  const code = $('pairInput').value.trim();
  if (!/^\d{6}$/.test(code)) { toast('请输入 6 位数字'); return; }
  if (await unlock(code)) { localStorage.setItem('phPair', code); $('lock').style.display = 'none'; }
}
async function unlock(code) {
  try {
    const enc = new TextEncoder();
    // token = SHA256(pairCode) hex —— 与 Mac 端一致
    const digest = await crypto.subtle.digest('SHA-256', enc.encode(code));
    token = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2,'0')).join('');
    // key = HKDF(pairCode, salt, info) —— 与 Mac 端同参数
    const base = await crypto.subtle.importKey('raw', enc.encode(code), 'HKDF', false, ['deriveKey']);
    key = await crypto.subtle.deriveKey(
      { name:'HKDF', hash:'SHA-256', salt: enc.encode('PasteHistory-Pairing-v1'),
        info: enc.encode('clip-payload') },
      base, { name:'AES-GCM', length:256 }, false, ['encrypt','decrypt']);
    const r = await api('/api/info');
    if (!r.ok) { toast('配对码不正确'); key = null; return false; }
    const info = await r.json();
    $('status').textContent = '已连接 ' + info.name + ' · ' + info.count + ' 条 · 端到端加密';
    return true;
  } catch (e) { toast('连接失败：' + e.message); return false; }
}

function api(path, opts) {
  return fetch(path, Object.assign({ headers: { 'X-Pair-Token': token } }, opts));
}

// ---- 解密：Mac 端 combined = nonce(12) + ciphertext + tag(16) ----
async function decryptB64(b64) {
  if (!b64) return null;
  const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const iv = raw.slice(0, 12), data = raw.slice(12);
  const plain = await crypto.subtle.decrypt({ name:'AES-GCM', iv }, key, data);
  return new TextDecoder().decode(plain);
}
async function decryptBytes(b64) {
  const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const iv = raw.slice(0, 12), data = raw.slice(12);
  return new Uint8Array(await crypto.subtle.decrypt({ name:'AES-GCM', iv }, key, data));
}

// ---- 拉取 + 解密 + 渲染 ----
async function load() {
  if (!key) return;
  try {
    const r = await api('/api/clips');
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const data = await r.json();
    const out = [];
    for (const c of data.clips) {
      const item = { id: c.id, kind: c.kind, ts: c.ts, pinned: c.pinned, img: c.img || null };
      try {
        const plain = JSON.parse(await decryptB64(c.payload) || '{}');
        item.text = plain.text || ''; item.ocr = plain.ocr || '';
        item.app = plain.app || ''; item.paths = plain.paths || '';
        item.thumb = plain.thumb || null;
      } catch (e) { item.text = '🔒 解密失败'; }
      out.push(item);
    }
    clips = out;
    render();
  } catch (e) { $('status').textContent = '连接失败，下拉重试'; }
}

function fmtTime(ts) {
  const d = new Date(ts * 1000), now = new Date();
  const diff = (now - d) / 1000;
  if (diff < 60) return '刚刚';
  if (diff < 3600) return Math.floor(diff/60) + ' 分钟前';
  const hm = d.toTimeString().slice(0,5);
  if (d.toDateString() === now.toDateString()) return '今天 ' + hm;
  return (d.getMonth()+1) + '-' + d.getDate() + ' ' + hm;
}
function summary(c) {
  if (c.kind === 'text') return c.text || '';
  if (c.kind === 'image') return c.ocr ? '🖼 ' + c.ocr.slice(0,60) : '🖼 图片';
  return '📁 ' + (c.paths || '').split('\n')[0];
}

function render() {
  const q = $('q').value.trim().toLowerCase();
  const list = clips.filter(c => !q ||
    (c.text||'').toLowerCase().includes(q) ||
    (c.ocr||'').toLowerCase().includes(q) ||
    (c.paths||'').toLowerCase().includes(q) ||
    (c.app||'').toLowerCase().includes(q));
  const el = $('list');
  if (!list.length) { el.innerHTML = '<div id="empty">' + (clips.length ? '没有匹配的内容' : '还没有记录') + '</div>'; return; }
  el.innerHTML = list.map(c => {
    const thumb = c.thumb ? '<img class="thumb" src="data:image/png;base64,' + c.thumb + '">' : '';
    const pin = c.pinned ? '<span class="badge pin">置顶</span>' : '';
    const kind = { text:'文本', image:'图片', files:'文件' }[c.kind] || c.kind;
    return '<div class="clip" onclick="openSheet(\'' + c.id + '\')">' + thumb +
      '<div class="content">' + esc(summary(c)) + '</div><div class="meta">' + pin +
      '<span class="badge">' + kind + '</span><span>' + esc(c.app||'') + '</span><span>' + fmtTime(c.ts) + '</span></div></div>';
  }).join('');
}
function esc(s) { return (s||'').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function openSheet(id) {
  const c = clips.find(x => x.id === id); if (!c) return;
  current = c;
  $('sheetTitle').textContent = ({text:'文本',image:'图片',files:'文件'})[c.kind] + ' · ' + fmtTime(c.ts) + (c.app ? ' · ' + c.app : '');
  $('detail').textContent = c.kind === 'text' ? c.text : (c.paths || c.ocr || '');
  $('overlay').style.display = 'flex';
  if (c.kind === 'image' && c.img) loadImg(c.img);
}
async function loadImg(name) {
  try {
    const r = await api('/api/image/' + name);
    if (!r.ok) return;
    const buf = new Uint8Array(await r.arrayBuffer());
    const iv = buf.slice(0,12), data = buf.slice(12);
    const plain = await crypto.subtle.decrypt({name:'AES-GCM', iv}, key, data);
    const blob = new Blob([plain], {type:'image/png'});
    const img = document.createElement('img'); img.src = URL.createObjectURL(blob);
    $('detail').prepend(img);
  } catch(e) {}
}
function closeSheet() { $('overlay').style.display = 'none'; }

async function copyCurrent() {
  if (!current) return;
  try {
    if (current.kind === 'text' || current.kind === 'files') {
      await navigator.clipboard.writeText(current.kind === 'text' ? current.text : current.paths);
      toast('已复制，去粘贴吧');
    } else { toast('图片请长按保存后使用'); }
    closeSheet();
  } catch (e) { toast('复制失败：' + e.message); }
}

// ---- 手机 → Mac：读本机剪贴板 → 加密上传 ----
async function syncClipboard() {
  if (!key) return;
  const btn = $('syncBtn');
  try {
    btn.disabled = true; btn.textContent = '读取中…';
    const t = await navigator.clipboard.readText();
    if (!t || !t.trim()) { toast('剪贴板是空的'); return; }
    btn.textContent = '同步中…';
    const payload = JSON.stringify({ text: t, kind: 'text', app: '手机网页' });
    const b64 = await encryptToB64(payload);
    const r = await api('/api/clips', { method:'POST', headers: {
      'Content-Type':'application/json', 'X-Pair-Token': token },
      body: JSON.stringify({ payload: b64 }) });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    toast('✅ 已同步到 Mac');
    btn.classList.add('on'); setTimeout(()=>btn.classList.remove('on'), 1200);
    await load();
  } catch (e) {
    if (String(e.message||e).includes('denied') || String(e).includes('NotAllowed'))
      toast('请在系统弹窗中允许读取剪贴板');
    else toast('同步失败：' + (e.message || e));
  } finally { btn.disabled = false; btn.textContent = '同步剪贴板'; }
}
async function encryptToB64(text) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({name:'AES-GCM', iv}, key, new TextEncoder().encode(text));
  const combined = new Uint8Array(12 + data.byteLength);
  combined.set(iv); combined.set(new Uint8Array(data), 12);
  return btoa(String.fromCharCode(...combined));
}

function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.style.opacity = 1;
  clearTimeout(t._h); t._h = setTimeout(() => t.style.opacity = 0, 2200);
}

let debounce;
$('q').addEventListener('input', () => { clearTimeout(debounce); debounce = setTimeout(render, 200); });
document.addEventListener('visibilitychange', () => { if (!document.hidden) load(); });

(async () => {
  if (await initPair()) { await load(); setInterval(load, 15000); }
})();
</script>
</body>
</html>
"""#
}
