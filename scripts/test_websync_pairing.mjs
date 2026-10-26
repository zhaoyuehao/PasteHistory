import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync('Sources/PasteHistory/Presentation/Sync/WebSyncPage.swift', 'utf8');
const fallback = source.slice(source.indexOf('function concatBytes'), source.indexOf('// ================= 回退实现结束'));
const initPair = source.slice(source.indexOf('async function initPair()'), source.indexOf('async function unlock('));
const fixtures = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

async function pair(hash, saved) {
  const storage = new Map(saved === undefined ? [] : [['phPair', saved]]);
  const result = { locked: false, code: null, cleaned: false };
  const context = vm.createContext({
    URLSearchParams, location: { hash },
    localStorage: { getItem: k => storage.get(k), setItem: (k, v) => storage.set(k, v), removeItem: k => storage.delete(k) },
    history: { replaceState: () => { result.cleaned = true; } },
    showLock: () => { result.locked = true; },
    unlock: async code => { result.code = code; return true; }
  });
  await vm.runInContext(initPair + '\ninitPair()', context);
  return { ...result, saved: storage.get('phPair') };
}

const context = vm.createContext({});
vm.runInContext(fallback, context);
const bytes = s => new TextEncoder().encode(s);
for (const f of fixtures) {
  const fromQR = await pair(new URL(f.url).hash, '000123');
  assert.equal(fromQR.code, f.code);
  assert.equal(fromQR.saved, f.code);
  assert.equal(fromQR.cleaned, true);
  assert.equal((await pair('', fromQR.saved)).code, f.code);
  const token = context.hexBytes(context.sha256(bytes(f.code)));
  assert.equal(token, f.token);
  assert.equal(token, crypto.createHash('sha256').update(f.code).digest('hex'));
  const key = context.hkdf256(bytes(f.code), bytes('PasteHistory-Pairing-v1'), bytes('clip-payload'), 32);
  assert.equal(Buffer.from(key).toString('base64'), f.key);
  assert.deepEqual(Buffer.from(key), Buffer.from(crypto.hkdfSync('sha256', bytes(f.code), bytes('PasteHistory-Pairing-v1'), bytes('clip-payload'), 32)));
  const sealed = Buffer.from(f.payload, 'base64');
  assert.equal(Buffer.from(context.aesGcmDecBytes(key, sealed.subarray(0, 12), sealed.subarray(12))).toString(), f.plain);
  for (const size of [0, 16, 30, 1024]) {
    const plain = crypto.randomBytes(size), iv = crypto.randomBytes(12);
    const encrypted = Buffer.from(context.aesGcmEncBytes(key, iv, plain));
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(encrypted.subarray(-16));
    assert.deepEqual(Buffer.concat([decipher.update(encrypted.subarray(0, -16)), decipher.final()]), plain);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const nodeEncrypted = Buffer.concat([cipher.update(plain), cipher.final(), cipher.getAuthTag()]);
    assert.deepEqual(Buffer.from(context.aesGcmDecBytes(key, iv, nodeEncrypted)), plain);
    nodeEncrypted[nodeEncrypted.length - 1] ^= 1;
    assert.equal(context.aesGcmDecBytes(key, iv, nodeEncrypted), null);
  }
}
for (const invalid of ['000123', '', 'short', 'Abcdefghijklm1! ', 'Abcdefghijklm12!extra']) {
  assert.equal((await pair('', invalid)).locked, true);
  const result = await pair('#pair=' + encodeURIComponent(invalid), fixtures[0].code);
  assert.equal(result.locked, true);
  assert.equal(result.saved, undefined);
}
assert.equal((await pair('#other=pair%3D000123', fixtures[0].code)).code, fixtures[0].code);
console.log(`PASS: generation, persistence, legacy migration, ${fixtures.length} QR round trips, Swift/JS/Node token/key and AES-GCM interoperability`);
