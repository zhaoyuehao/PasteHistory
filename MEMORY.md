# MEMORY.md（PasteHistory 长期记忆）

## 项目是什么

macOS 菜单栏常驻的剪贴板历史：⌘C 自动记录 → ⇧⌘V 唤起面板 → 搜索 → 单击预览、回车把内容贴回原输入框。
SQLite 持久化 + iCloud Drive 多设备同步 + 局域网 PWA 让手机加入同一个剪贴板。

## 已定的架构决策（不要再改回）

- **只保留许愿树界面**：列表及 ⌘L 切换已删除，忽略旧 `showDesktopTree` 偏好。⌘⇧V 唤起，单击预览，Delete 删除，回车粘贴。

- **不用 Xcode 工程**：SwiftPM + `scripts/build_app.sh` 手工打 .app，便于脚本化与 CLI 维护参数。
- **持久化用 SQLite3 C API** 而非 Core Data：图片原图落盘在 `Application Support/PasteHistory/images/`，DB 只存文件名，避免内存里堆图。
- **iCloud 同步一记录一文件**（`clips/<uuid>.json`）+ `tombstones/` 墓碑 + 60s 对账：冲突少、可部分恢复；`--restore-images` 能从远端补回本地丢的原图。
- **跨设备不做服务端**：局域网 HTTP + 配对码派生的端到端加密（AES-256-GCM），手机浏览器直接用，不用装 App、不用开发者账号。
- **跨设备密钥派生**：`token = SHA256(配对码)hex`；`key = HKDF-SHA256(配对码, salt="PasteHistory-Pairing-v1", info="clip-payload", 32B)`；`payload = base64(nonce12 + ct + tag16)`。改任何一端都要同步改另一端。
- **接力来源标注**：识别 `com.apple.is-remote-clipboard` 打「接力 · iPhone/iPad」标记；`ConcealedType`/`TransientType`（密码框、1Password 等）**不记录**。

## 非 Secure Context 的三条硬限制（手机端 HTTP 局域网地址）

1. **`crypto.subtle` 不存在** → 页面内嵌纯 JS SHA-256/HMAC/HKDF/AES-256-GCM 回退（与 Mac 端同参数）。
2. **`navigator.clipboard` 不存在** → 写走 `document.execCommand('copy')`；**读无任何 API 可用**，改为「粘贴框」交互（长按粘贴 → 加密上传）。
3. **Service Worker 无法注册** → 不存在离线 PWA；只能靠 `apple-mobile-web-app-capable` 做主屏全屏体验。

想恢复手机端原生体验（自动读剪贴板、可离线）**唯一办法是 HTTPS**（自有域名证书指向局域网 IP，或手机信任自签证书）。

## 反复踩过的坑

- **TCC 权限按签名身份匹配**：ad-hoc 签名每次重建都失效 → 必须 Apple Development 证书签名。已授权仍弹窗时，去系统设置里删掉多余的 PasteHistory 条目再重勾。
- **macOS 14 `activate(ignoringOtherApps:)` 失效** → 统一用 `NSApp.activate()`。
- **面板二次打不开**：`hide()` 里 0.05s 延迟的 `previousApp.activate()` 会把刚打开的面板顶掉 → `showGeneration` 代数计数器作废过期激活；`windowDidResignKey` 要判 `isVisible` 防重入。
- **NSBox 关掉 autoresizing 又不加约束** → 尺寸塌成 0（二维码空白就是这么来的），要么显式加约束，要么别关。
- **菜单跟踪 runloop 阻塞 MainActor** → HTTP 服务必须独立队列 + 独立 SQLite 读连接。
- **GHASH 输入必须先 pad 密文到 16 倍数再接长度块**：NIST 的 16 字节整块向量测不出来，非整倍数（30B）才暴露。
- **`String.fromCharCode(...大数组)` 有参数上限** → 长文本同步要 8KB 分块转 base64。
- **移动项目目录后模块缓存报错** → `rm -rf .build` 重建。

## 加密自测方法（改加密代码后必做）

把页面里的纯 JS 回退实现抽出来，用 node 内置 `crypto` 交叉验证：

- SHA-256 / HMAC / HKDF 对齐 `crypto.createHash` / `createHmac` / `hkdfSync`
- AES：FIPS-197 已知向量；GCM：NIST 向量 + 与 `createCipheriv('aes-256-gcm')` 互加互解 + 篡改 tag 必须失败
- 端到端：拿 `defaults read com.verdent.pastehistory webSyncPairCode` 的配对码，`GET /api/clips` 全量解密 + `POST /api/clips` 加密回传，验证 200

## 仍存在的已知限制

- iOS「本地网络」权限弹窗若被拒 → 手机连不上；Wi-Fi 开设备隔离（AP isolation）时同样连不上。
- macOS 防火墙首次入站连接需允许 PasteHistory。
- 配对码 6 位（100 万组合），已有 401 限速（60s/10 次 → 429）兜底。
- `/api/clips` 一次返回最多 300 条（含缩略图 base64），手机端靠 `decCache` 避免重复解密。
- 元数据（id / kind / 时间戳 / 图片名）是明文传输，只有内容密文。
