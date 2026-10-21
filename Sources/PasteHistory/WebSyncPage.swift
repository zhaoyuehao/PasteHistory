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
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.json">
<title id="pageTitle">剪贴板</title>
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
         transition: opacity .25s; pointer-events: none; z-index: 30; max-width: 85vw; text-align: center;
         display: flex; align-items: center; justify-content: center; gap: 7px; }
#toastIcon { line-height: 0; }
#toastIcon svg { display: block; }
#lock { position: fixed; inset: 0; background: #1c1c1e; z-index: 40; display: none;
        flex-direction: column; align-items: center; justify-content: center; gap: 14px; padding: 30px; }
#lock p { color: #98989f; font-size: 13px; text-align: center; line-height: 1.6; }
/* 非 Secure Context 下没有剪贴板 API：用粘贴框代替"读取剪贴板" */
#pasteOverlay { position: fixed; inset: 0; background: rgba(0,0,0,.55); display: none; z-index: 25;
                padding: 20px; align-items: center; justify-content: center; }
#pbSheet { background: #2c2c2e; border-radius: 16px; width: 100%; max-width: 500px; padding: 14px 16px; }
#pbTitle { font-size: 12px; color: #98989f; line-height: 1.6; margin-bottom: 10px; }
#pb { width: 100%; height: 130px; background: #1c1c1e; border: 1px solid #48484a; border-radius: 10px;
      color: #f2f2f7; font-size: 16px; padding: 10px 12px; resize: none; outline: none; }
#pbBtn { background: #0a84ff; color: #fff; border: none; border-radius: 10px; padding: 11px 0; width: 100%;
         font-size: 16px; font-weight: 600; margin-top: 10px; }
</style>
</head>
<body>
<header>
  <h1 id="heading">剪贴板历史</h1>
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
<div id="toast"><span id="toastIcon"></span><span id="toastText"></span></div>
<div id="lock">
  <p id="pairHint">重新扫码或打开 Mac 上的链接<br>即可自动解锁</p>
</div>
<div id="pasteOverlay" onclick="if(event.target===this)closePasteBox()">
  <div id="pbSheet">
    <div id="pbTitle">当前页面不是 HTTPS，浏览器不允许网页读取剪贴板。<br>请在下面长按 → 粘贴，再同步到 Mac。</div>
    <textarea id="pb" placeholder="长按此处 → 粘贴"></textarea>
    <button id="pbBtn" onclick="submitPasted()">同步到 Mac</button>
  </div>
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
// The phone page follows the browser language; Chinese variants keep the original copy.
const browserLanguage = (navigator.language || '').toLowerCase();
const ui = browserLanguage.startsWith('zh-hant') || browserLanguage.startsWith('zh-tw') || browserLanguage.startsWith('zh-hk') ? {
  title:'剪貼簿', heading:'剪貼簿歷史', phoneWeb:'手機網頁', connecting:'連線中…', search:'搜尋（含圖片中文字）', sync:'同步剪貼簿', pasteSync:'貼上同步', loading:'載入中…', copy:'複製', pairHint:'重新掃描或開啟 Mac 上的連結<br>即可自動解鎖', pasteHint:'目前頁面不是 HTTPS，瀏覽器不允許網頁讀取剪貼簿。<br>請在下方長按 → 貼上，再同步到 Mac。', pastePlaceholder:'長按此處 → 貼上', syncMac:'同步到 Mac', wrongPair:'配對碼已失效，請重新掃描', connected:'已連線', secure:'端對端加密', js:'（JS）', failed:'連線失敗：', offline:'無法連線 Mac：確認同一 Wi-Fi（部分 Wi-Fi 會隔離裝置）、已允許「區域網路」權限、Mac 未睡眠', justNow:'剛剛', minutes:'{n} 分鐘前', today:'今天 ', noMatch:'沒有符合的內容', noItems:'還沒有記錄', pinned:'置頂', text:'文字', image:'圖片', files:'檔案', imageSave:'圖片請長按儲存後使用', copied:'已複製，請到目標 App 貼上', copyBlocked:'自動複製被瀏覽器阻止，請長按選取上方內容後點「拷貝」', emptyClipboard:'剪貼簿是空的', reading:'讀取中…', syncing:'同步中…', allowRead:'請在系統彈窗中允許讀取剪貼簿', syncFailed:'同步失敗：', pasteSomething:'先貼上內容', synced:'已同步到 Mac', decryptFailed:'解密失敗', decryptCheckFailed:'AES-GCM 驗證失敗', portSecure:'端對端加密'
} : browserLanguage.startsWith('zh') ? {
  title:'剪贴板', heading:'剪贴板历史', phoneWeb:'手机网页', connecting:'连接中…', search:'搜索（含图片内文字）', sync:'同步剪贴板', pasteSync:'粘贴同步', loading:'加载中…', copy:'复制', pairHint:'重新扫码或打开 Mac 上的链接<br>即可自动解锁', pasteHint:'当前页面不是 HTTPS，浏览器不允许网页读取剪贴板。<br>请在下面长按 → 粘贴，再同步到 Mac。', pastePlaceholder:'长按此处 → 粘贴', syncMac:'同步到 Mac', wrongPair:'配对码已失效，请重新扫码', connected:'已连接', secure:'端到端加密', js:'（JS）', failed:'连接失败：', offline:'连不上 Mac：确认同一 Wi-Fi（部分 Wi-Fi 有设备隔离）、已允许「本地网络」权限、Mac 未睡眠', justNow:'刚刚', minutes:'{n} 分钟前', today:'今天 ', noMatch:'没有匹配的内容', noItems:'还没有记录', pinned:'置顶', text:'文本', image:'图片', files:'文件', imageSave:'图片请长按保存后使用', copied:'已复制，去粘贴吧', copyBlocked:'自动复制被浏览器阻止，请长按选中上方内容后点「拷贝」', emptyClipboard:'剪贴板是空的', reading:'读取中…', syncing:'同步中…', allowRead:'请在系统弹窗中允许读取剪贴板', syncFailed:'同步失败：', pasteSomething:'先粘贴点内容', synced:'已同步到 Mac', decryptFailed:'解密失败', decryptCheckFailed:'AES-GCM 校验失败', portSecure:'端到端加密'
} : {
  title:'Clipboard', heading:'Clipboard History', phoneWeb:'Phone web page', connecting:'Connecting…', search:'Search (including text in images)', sync:'Sync Clipboard', pasteSync:'Paste to Sync', loading:'Loading…', copy:'Copy', pairHint:'Scan the QR code or open the link on your Mac<br>to unlock automatically', pasteHint:'This page is not HTTPS, so the browser cannot read the clipboard.<br>Long-press below to paste, then sync to your Mac.', pastePlaceholder:'Long-press here to paste', syncMac:'Sync to Mac', wrongPair:'Pairing code expired — scan the QR code again', connected:'Connected', secure:'End-to-end encrypted', js:' (JS)', failed:'Connection failed: ', offline:'Cannot reach Mac: check the same Wi-Fi, Local Network permission, and that the Mac is awake', justNow:'Just now', minutes:'{n} min ago', today:'Today ', noMatch:'No matches', noItems:'No records yet', pinned:'Pinned', text:'Text', image:'Image', files:'Files', imageSave:'Long-press the image to save it', copied:'Copied. Paste it in the target app.', copyBlocked:'Automatic copy was blocked. Long-press the content above and choose Copy.', emptyClipboard:'The clipboard is empty', reading:'Reading…', syncing:'Syncing…', allowRead:'Allow clipboard access in the system prompt', syncFailed:'Sync failed: ', pasteSomething:'Paste some content first', synced:'Synced to Mac', decryptFailed:'Decryption failed', decryptCheckFailed:'AES-GCM verification failed', portSecure:'End-to-end encrypted'
};
function tr(key, value) { return (ui[key] || key).replace('{n}', value == null ? '' : value); }
document.documentElement.lang = browserLanguage.startsWith('zh') ? browserLanguage : 'en';
document.title = tr('title'); $('heading').textContent = tr('heading'); $('status').textContent = tr('connecting'); $('q').placeholder = tr('search'); $('syncBtn').textContent = tr('sync'); $('empty').textContent = tr('loading'); $('copyBtn').textContent = tr('copy'); $('pairHint').innerHTML = tr('pairHint'); $('pbTitle').innerHTML = tr('pasteHint'); $('pb').placeholder = tr('pastePlaceholder'); $('pbBtn').textContent = tr('syncMac');
const decCache = new Map();   // 密文 → 明文缓存（避免轮询重复解密）
const hasSubtle = !!(window.crypto && window.crypto.subtle);
// 非安全上下文（http://局域网IP）下 navigator.clipboard 为 undefined，读写剪贴板都要走回退
const canClipboard = !!(navigator.clipboard && navigator.clipboard.readText && navigator.clipboard.writeText);

// ---- 配对码：URL fragment 优先，其次 localStorage ----
async function initPair() {
  const m = location.hash.match(/pair=(\d{6})/);
  if (m) { localStorage.setItem('phPair', m[1]); history.replaceState(null,'','/'); }
  let code = localStorage.getItem('phPair');
  if (!code) { $('lock').style.display = 'flex'; return false; }
  return await unlock(code);
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
    if (!r.ok) { toast(tr('wrongPair'), 'warn'); key = null; keyBytes = null; return false; }
    const info = await r.json();
    $('status').textContent = tr('connected') + ' ' + info.name + ' · ' + info.count + ' · ' + tr('secure') + (hasSubtle ? '' : tr('js'));
    if (!canClipboard) $('syncBtn').textContent = tr('pasteSync');
    return true;
  } catch (e) { toast(tr('failed') + e.message, 'warn'); return false; }
}

function api(path, opts) {
  return fetch(path, Object.assign({ headers: { 'X-Pair-Token': token } }, opts));
}

// ---- 加解密封装：有 WebCrypto 用原生，否则纯 JS 回退 ----
async function gcmDecrypt(iv, data) { // data = ct + tag
  if (hasSubtle) return new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM', iv}, key, data));
  const pt = aesGcmDecBytes(keyBytes, iv, data);
  if (!pt) throw new Error(tr('decryptCheckFailed'));
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
      // 密文不变就复用上次解密结果，避免每次轮询把几百条重解一遍（纯 JS 回退下很吃 CPU）
      const ck = c.id + ':' + c.payload.length + ':' + c.payload.slice(-24);
      let plain = decCache.get(ck);
      if (!plain) {
        try {
          plain = JSON.parse(await decryptB64(c.payload) || '{}');
          decCache.set(ck, plain);
        } catch (e) { plain = null; }
      }
      if (plain) {
        item.text = plain.text || ''; item.ocr = plain.ocr || '';
        item.app = plain.app || ''; item.paths = plain.paths || '';
        item.thumb = plain.thumb || null;
      } else { item.text = tr('decryptFailed'); }
      out.push(item);
    }
    if (decCache.size > 1000) decCache.clear();
    clips = out;
    render();
  } catch (e) {
    $('status').textContent = tr('offline');
  }
}

function fmtTime(ts) {
  const d = new Date(ts * 1000), now = new Date();
  const diff = (now - d) / 1000;
  if (diff < 60) return tr('justNow');
  if (diff < 3600) return tr('minutes', Math.floor(diff/60));
  const hm = d.toTimeString().slice(0,5);
  if (d.toDateString() === now.toDateString()) return tr('today') + hm;
  return (d.getMonth()+1) + '-' + d.getDate() + ' ' + hm;
}
function summary(c) {
  if (c.kind === 'text') return c.text || '';
  if (c.kind === 'image') return c.ocr ? '🖼 ' + c.ocr.slice(0,60) : '🖼 ' + tr('image');
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
  if (!list.length) { el.innerHTML = '<div id="empty">' + (clips.length ? tr('noMatch') : tr('noItems')) + '</div>'; return; }
  el.innerHTML = list.map(c => {
    const thumb = c.thumb ? '<img class="thumb" src="data:image/png;base64,' + c.thumb + '">' : '';
    const pin = c.pinned ? '<span class="badge pin">' + tr('pinned') + '</span>' : '';
    const kind = { text:tr('text'), image:tr('image'), files:tr('files') }[c.kind] || c.kind;
    return '<div class="clip" onclick="openSheet(\'' + c.id + '\')">' + thumb +
      '<div class="content">' + esc(summary(c)) + '</div><div class="meta">' + pin +
      '<span class="badge">' + kind + '</span><span>' + esc(c.app||'') + '</span><span>' + fmtTime(c.ts) + '</span></div></div>';
  }).join('');
}
function esc(s) { return (s||'').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function openSheet(id) {
  const c = clips.find(x => x.id === id); if (!c) return;
  current = c;
  $('sheetTitle').textContent = ({text:tr('text'),image:tr('image'),files:tr('files')})[c.kind] + ' · ' + fmtTime(c.ts) + (c.app ? ' · ' + c.app : '');
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

// ---- 复制：Clipboard API 仅在安全上下文可用，非 HTTPS 回退 execCommand ----
async function copyCurrent() {
  if (!current) return;
  if (current.kind === 'image') { toast(tr('imageSave')); closeSheet(); return; }
  const text = current.kind === 'text' ? current.text : current.paths;
  if (canClipboard) {
    try {
      await navigator.clipboard.writeText(text);
      toast(tr('copied'), 'ok'); closeSheet(); return;
    } catch (e) { /* 落到下面的回退 */ }
  }
  if (legacyCopy(text)) { toast(tr('copied'), 'ok'); closeSheet(); return; }
  toast(tr('copyBlocked'), 'warn');
}

function legacyCopy(text) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.contentEditable = 'true';
  ta.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;padding:0;border:none;opacity:0;';
  document.body.appendChild(ta);
  const sel = window.getSelection();
  const saved = sel && sel.rangeCount ? sel.getRangeAt(0) : null;
  let ok = false;
  try {
    const range = document.createRange();
    range.selectNodeContents(ta);
    sel.removeAllRanges(); sel.addRange(range);
    ta.setSelectionRange(0, text.length);
    ok = document.execCommand('copy');
  } catch (e) { ok = false; }
  ta.remove();
  if (saved) { sel.removeAllRanges(); sel.addRange(saved); }
  return ok;
}

// ---- 手机 → Mac：优先直接读剪贴板，读不到就用粘贴框 ----
async function syncClipboard() {
  if (!keyBytes) return;
  if (!canClipboard) { openPasteBox(); return; }
  const btn = $('syncBtn');
  try {
    btn.disabled = true; btn.textContent = tr('reading');
    const t = await navigator.clipboard.readText();
    if (!t || !t.trim()) { toast(tr('emptyClipboard'), 'warn'); return; }
    btn.textContent = tr('syncing');
    await uploadText(t);
    btn.classList.add('on'); setTimeout(()=>btn.classList.remove('on'), 1200);
  } catch (e) {
    if (String(e.message||e).includes('denied') || String(e).includes('NotAllowed'))
      toast(tr('allowRead'), 'warn');
    else toast(tr('syncFailed') + (e.message || e), 'warn');
  } finally { btn.disabled = false; btn.textContent = tr('sync'); }
}

function openPasteBox() {
  $('pb').value = '';
  $('pasteOverlay').style.display = 'flex';
  setTimeout(() => { try { $('pb').focus(); } catch (e) {} }, 60);
}
function closePasteBox() { $('pasteOverlay').style.display = 'none'; }
async function submitPasted() {
  const t = $('pb').value.trim();
  if (!t) { toast(tr('pasteSomething'), 'warn'); return; }
  const btn = $('pbBtn');
  btn.disabled = true; btn.textContent = tr('syncing');
  try { await uploadText(t); closePasteBox(); }
  catch (e) { toast(tr('syncFailed') + (e.message || e), 'warn'); }
  finally { btn.disabled = false; btn.textContent = tr('syncMac'); }
}

async function uploadText(t) {
  const payload = JSON.stringify({ text: t, kind: 'text', app: tr('phoneWeb') });
  const b64 = await encryptToB64(payload);
  const r = await api('/api/clips', { method:'POST', headers: {
    'Content-Type':'application/json', 'X-Pair-Token': token },
    body: JSON.stringify({ payload: b64 }) });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  toast(tr('synced'), 'ok');
  await load();
}
async function encryptToB64(text) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await gcmEncrypt(iv, new TextEncoder().encode(text));
  const combined = new Uint8Array(12 + data.byteLength);
  combined.set(iv); combined.set(new Uint8Array(data), 12);
  return bytesToB64(combined);
}
// 分块转换：String.fromCharCode(...bigArray) 参数过多会 RangeError（长文同步会失败）
function bytesToB64(bytes) {
  let out = '';
  const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH)
    out += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
  return btoa(out);
}

// 状态图标用内联 SVG，不用 emoji：同一句话在 iOS / Android / 桌面会被渲染成三种
// 不同的图形，还带着系统彩色 emoji 的配色，跟页面这套冷灰凑不到一起
var ICON = {
  ok: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  warn: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 2 20h20L12 3z"/><path d="M12 10v4"/><path d="M12 17h.01"/></svg>'
};

function toast(msg, icon) {
  var t = $('toast'), ic = $('toastIcon');
  // 提示语里拼了 e.message，只能走 textContent；图标是常量，才敢用 innerHTML
  // 显隐走内联样式：stylesheet 里的 display:none 会盖住 ''
  ic.innerHTML = (icon && ICON[icon]) || '';
  ic.style.display = (icon && ICON[icon]) ? 'inline-flex' : 'none';
  $('toastText').textContent = msg;
  t.style.opacity = 1;
  clearTimeout(t._h); t._h = setTimeout(function () { t.style.opacity = 0; }, 2200);
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
