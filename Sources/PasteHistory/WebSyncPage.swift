import Foundation

/// 手机端网页：单文件内嵌 HTML。剪贴板历史以密文传输，
/// 页面内用 WebCrypto（HKDF 派生 AES-256-GCM，与 Mac 端同参数）解密显示；
/// 局域网 HTTP 地址下 crypto.subtle 不存在（非 Secure Context），自动回退到纯 JS 实现。
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
// ============================================================
// 纯 JS 加密回退：crypto.subtle 不存在（HTTP 局域网地址）时使用
// 参数与 Mac 端 CryptoKit / WebCrypto 完全一致（已过 NIST/RFC5869 向量自测）：
//   token = SHA-256(配对码) hex
//   key   = HKDF-SHA256(配对码, salt="PasteHistory-Pairing-v1", info="clip-payload", 32B)
//   payload = AES-256-GCM(key, nonce12) → nonce + ciphertext + tag16
// ============================================================
function concatBytes(...arrs) {
  const n = arrs.reduce((s, a) => s + a.length, 0);
  const out = new Uint8Array(n);
  let o = 0;
  for (const a of arrs) { out.set(a, o); o += a.length; }
  return out;
}

const SHA256_K = new Uint32Array([
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
]);

function sha256(bytes) {
  let h0=0x6a09e667,h1=0xbb67ae85,h2=0x3c6ef372,h3=0xa54ff53a,
      h4=0x510e527f,h5=0x9b05688c,h6=0x1f83d9ab,h7=0x5be0cd19;
  const bitLen = bytes.length * 8;
  const padLen = (((bytes.length + 8) >> 6) + 1) << 6;
  const buf = new Uint8Array(padLen);
  buf.set(bytes); buf[bytes.length] = 0x80;
  const dv = new DataView(buf.buffer);
  dv.setUint32(padLen - 8, Math.floor(bitLen / 0x100000000));
  dv.setUint32(padLen - 4, bitLen >>> 0);
  const w = new Int32Array(64);
  for (let i = 0; i < padLen; i += 64) {
    for (let j = 0; j < 16; j++) w[j] = dv.getInt32(i + j * 4);
    for (let j = 16; j < 64; j++) {
      const x = w[j-15], y = w[j-2];
      const s0 = ((x>>>7)|(x<<25)) ^ ((x>>>18)|(x<<14)) ^ (x>>>3);
      const s1 = ((y>>>17)|(y<<15)) ^ ((y>>>19)|(y<<13)) ^ (y>>>10);
      w[j] = (w[j-16] + s0 + w[j-7] + s1) | 0;
    }
    let a=h0,b=h1,c=h2,d=h3,e=h4,f=h5,g=h6,hh=h7;
    for (let j = 0; j < 64; j++) {
      const S1 = ((e>>>6)|(e<<26)) ^ ((e>>>11)|(e<<21)) ^ ((e>>>25)|(e<<7));
      const t1 = (hh + S1 + ((e&f)^(~e&g)) + SHA256_K[j] + w[j]) | 0;
      const S0 = ((a>>>2)|(a<<30)) ^ ((a>>>13)|(a<<19)) ^ ((a>>>22)|(a<<10));
      const t2 = (S0 + ((a&b)^(a&c)^(b&c))) | 0;
      hh=g; g=f; f=e; e=(d+t1)|0; d=c; c=b; b=a; a=(t1+t2)|0;
    }
    h0=(h0+a)|0; h1=(h1+b)|0; h2=(h2+c)|0; h3=(h3+d)|0;
    h4=(h4+e)|0; h5=(h5+f)|0; h6=(h6+g)|0; h7=(h7+hh)|0;
  }
  const out = new Uint8Array(32);
  const odv = new DataView(out.buffer);
  [h0,h1,h2,h3,h4,h5,h6,h7].forEach((v, i) => odv.setUint32(i*4, v >>> 0));
  return out;
}

function hmac256(key, data) {
  let k = key;
  if (k.length > 64) k = sha256(k);
  const ipad = new Uint8Array(64).fill(0x36), opad = new Uint8Array(64).fill(0x5c);
  for (let i = 0; i < k.length; i++) { ipad[i] ^= k[i]; opad[i] ^= k[i]; }
  return sha256(concatBytes(opad, sha256(concatBytes(ipad, data))));
}

function hkdf256(ikm, salt, info, len) {
  const prk = hmac256(salt, ikm);
  const out = new Uint8Array(len);
  let t = new Uint8Array(0), off = 0;
  for (let i = 1; off < len; i++) {
    t = hmac256(prk, concatBytes(t, info, new Uint8Array([i])));
    out.set(t.subarray(0, Math.min(32, len - off)), off);
    off += 32;
  }
  return out;
}

const AES_SBOX = new Uint8Array([
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
]);
const AES_RCON = [0x01,0x02,0x04,0x08,0x10,0x20,0x40];

function aes256ExpandKey(key) { // 32B key -> Uint32Array(60)
  const w = new Uint32Array(60);
  for (let i = 0; i < 8; i++)
    w[i] = ((key[4*i]<<24) | (key[4*i+1]<<16) | (key[4*i+2]<<8) | key[4*i+3]) >>> 0;
  const subWord = x =>
    ((AES_SBOX[x>>>24]<<24) | (AES_SBOX[(x>>>16)&0xff]<<16) |
     (AES_SBOX[(x>>>8)&0xff]<<8) | AES_SBOX[x&0xff]) >>> 0;
  const rotWord = x => ((x<<8) | (x>>>24)) >>> 0;
  for (let i = 8; i < 60; i++) {
    let t = w[i-1];
    if (i % 8 === 0) t = (subWord(rotWord(t)) ^ (AES_RCON[i/8 - 1] << 24)) >>> 0;
    else if (i % 8 === 4) t = subWord(t);
    w[i] = (w[i-8] ^ t) >>> 0;
  }
  return w;
}

function aesEncryptBlock(rk, s) { // s: Uint8Array(16) 就地加密
  const xt = b => ((b << 1) ^ ((b & 0x80) ? 0x1b : 0)) & 0xff;
  const addKey = r => { for (let c = 0; c < 4; c++) {
    const w = rk[r*4+c];
    s[4*c] ^= (w>>>24)&0xff; s[4*c+1] ^= (w>>>16)&0xff; s[4*c+2] ^= (w>>>8)&0xff; s[4*c+3] ^= w&0xff;
  }};
  addKey(0);
  for (let r = 1; r <= 14; r++) {
    for (let i = 0; i < 16; i++) s[i] = AES_SBOX[s[i]];
    // ShiftRows：state 按列排，行 i 左移 i
    let t;
    t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
    t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
    t=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=s[3]; s[3]=t;
    if (r < 14) { // MixColumns
      for (let c = 0; c < 4; c++) {
        const i = 4*c, a0=s[i], a1=s[i+1], a2=s[i+2], a3=s[i+3];
        s[i]   = xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
        s[i+1] = a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
        s[i+2] = a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
        s[i+3] = xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
      }
    }
    addKey(r);
  }
}

function gcmMul(x, y) { // GF(2^128) 乘法（GHASH 用）
  const z = new Uint8Array(16), v = Uint8Array.from(y);
  for (let i = 0; i < 128; i++) {
    if ((x[i>>3] >> (7-(i&7))) & 1)
      for (let j = 0; j < 16; j++) z[j] ^= v[j];
    const lsb = v[15] & 1;
    for (let j = 15; j > 0; j--) v[j] = (v[j]>>>1) | ((v[j-1]&1)<<7);
    v[0] >>>= 1;
    if (lsb) v[0] ^= 0xe1;
  }
  return z;
}

function ghash(hKey, data) {
  let y = new Uint8Array(16);
  const padded = Math.ceil(data.length / 16) * 16;
  for (let i = 0; i < padded; i += 16) {
    for (let j = 0; j < 16; j++) y[j] ^= data[i+j] || 0;
    y = gcmMul(y, hKey);
  }
  return y;
}

function inc32(ctr) {
  for (let i = 15; i >= 12; i--) { ctr[i] = (ctr[i] + 1) & 0xff; if (ctr[i]) break; }
}

function aesCtr(rk, j0, data) { // CTR 从 inc32(J0) 开始，加解密同一函数
  const ctr = Uint8Array.from(j0);
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i += 16) {
    inc32(ctr);
    const s = Uint8Array.from(ctr);
    aesEncryptBlock(rk, s);
    const n = Math.min(16, data.length - i);
    for (let j = 0; j < n; j++) out[i+j] = data[i+j] ^ s[j];
  }
  return out;
}

function gcmTag(rk, hKey, j0, ct) {
  const lens = new Uint8Array(16);
  new DataView(lens.buffer).setUint32(12, ct.length * 8);
  // ct 先补零到 16 的倍数，再接长度块（NIST GCM 定义）
  const paddedCt = new Uint8Array(Math.ceil(Math.max(ct.length, 1) / 16) * 16);
  paddedCt.set(ct);
  const s = ghash(hKey, concatBytes(paddedCt, lens));
  const e = Uint8Array.from(j0);
  aesEncryptBlock(rk, e);
  const tag = new Uint8Array(16);
  for (let j = 0; j < 16; j++) tag[j] = s[j] ^ e[j];
  return tag;
}

function aesGcmEncBytes(keyBytes, iv, plain) { // -> ct + tag16
  const rk = aes256ExpandKey(keyBytes);
  const h = new Uint8Array(16); aesEncryptBlock(rk, h);
  const j0 = concatBytes(iv, new Uint8Array([0,0,0,1]));
  const ct = aesCtr(rk, j0, plain);
  return concatBytes(ct, gcmTag(rk, h, j0, ct));
}

function aesGcmDecBytes(keyBytes, iv, data) { // data = ct + tag16，校验失败返回 null
  const rk = aes256ExpandKey(keyBytes);
  const h = new Uint8Array(16); aesEncryptBlock(rk, h);
  const j0 = concatBytes(iv, new Uint8Array([0,0,0,1]));
  const ct = data.subarray(0, data.length - 16);
  const expect = gcmTag(rk, h, j0, ct);
  let diff = 0;
  for (let j = 0; j < 16; j++) diff |= expect[j] ^ data[data.length - 16 + j];
  if (diff !== 0) return null;
  return aesCtr(rk, j0, ct);
}

function hexBytes(b) { return [...b].map(x => x.toString(16).padStart(2,'0')).join(''); }
// ================= 回退实现结束 =================

const $ = id => document.getElementById(id);
let key = null, keyBytes = null, token = null, clips = [], current = null;
const hasSubtle = !!(window.crypto && window.crypto.subtle);

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
    const codeBytes = enc.encode(code);
    // token = SHA256(pairCode) hex —— 与 Mac 端一致
    token = hexBytes(sha256(codeBytes));
    // key = HKDF-SHA256(pairCode, salt, info) —— 与 Mac 端同参数
    keyBytes = hkdf256(codeBytes, enc.encode('PasteHistory-Pairing-v1'), enc.encode('clip-payload'), 32);
    if (hasSubtle) {
      key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt','decrypt']);
    }
    const r = await api('/api/info');
    if (!r.ok) { toast('配对码不正确'); key = null; keyBytes = null; return false; }
    const info = await r.json();
    $('status').textContent = '已连接 ' + info.name + ' · ' + info.count + ' 条 · 端到端加密' + (hasSubtle ? '' : '（JS）');
    return true;
  } catch (e) { toast('连接失败：' + e.message); return false; }
}

function api(path, opts) {
  return fetch(path, Object.assign({ headers: { 'X-Pair-Token': token } }, opts));
}

// ---- 加解密封装：有 WebCrypto 用原生，否则纯 JS 回退 ----
async function gcmDecrypt(iv, data) { // data = ct + tag
  if (hasSubtle) return new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM', iv}, key, data));
  const pt = aesGcmDecBytes(keyBytes, iv, data);
  if (!pt) throw new Error('AES-GCM 校验失败');
  return pt;
}
async function gcmEncrypt(iv, data) {
  if (hasSubtle) return new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM', iv}, key, data));
  return aesGcmEncBytes(keyBytes, iv, data);
}

// ---- 解密：Mac 端 combined = nonce(12) + ciphertext + tag(16) ----
async function decryptB64(b64) {
  if (!b64) return null;
  const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const plain = await gcmDecrypt(raw.slice(0, 12), raw.slice(12));
  return new TextDecoder().decode(plain);
}
async function decryptBytes(b64) {
  const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  return gcmDecrypt(raw.slice(0, 12), raw.slice(12));
}

// ---- 拉取 + 解密 + 渲染 ----
async function load() {
  if (!keyBytes) return;
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
    const plain = await gcmDecrypt(buf.slice(0,12), buf.slice(12));
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
  if (!keyBytes) return;
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
  const data = await gcmEncrypt(iv, new TextEncoder().encode(text));
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
