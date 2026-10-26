# 同步：使用、协议与验证

[文档索引](README.md) · [用户指南](../README.md#跨设备使用) · [开发与排障](development.md)

PasteHistory 有两条独立路径：iCloud Drive 在 Mac 之间同步文件，手机浏览器通过 Mac 内置的 HTTP 服务收发内容。系统通用剪贴板则由 macOS 提供；应用只记录已经到达 Mac 的内容。

## 手机配对与操作

服务随应用启动，默认端口 `8377`。Mac 保持运行且手机能访问其局域网地址后，在菜单栏打开配对面板，扫码或打开完整链接：

```text
http://<Mac的局域网IP>:8377/#pair=<6位配对码>
```

当前网页通过 URL fragment 或浏览器 `localStorage.phPair` 取得配对码，没有手工输入配对码的表单。二维码面板的刷新操作会轮换配对码、鉴权 token 和密钥，旧客户端需重新扫码；单纯重新打开面板不会轮换。

手机在 HTTP 页面上使用「粘贴同步」：长按粘贴文本，再上传。当前网页没有上传图片或文件的交互，即使服务端解析器包含这些类型的分支，也不能视为手机产品已支持它们。

Mac 记录下发后，手机可复制文本 / 文件路径、长按保存图片。`GET /api/clips` 最多返回按数据库排序的 300 条，手机只在这批结果中搜索；原图另行按需下载。

### HTTP 页面的能力边界

| 能力 | 当前处理 |
| --- | --- |
| WebCrypto `crypto.subtle` | 不可用时使用页面内纯 JS SHA-256 / HMAC / HKDF / AES-GCM 回退 |
| Clipboard API | 不可用时用粘贴框接收文本；复制尝试 `execCommand('copy')`，失败提示手动选中复制 |
| Service Worker | 当前局域网 HTTP 页面不提供离线能力；主屏图标只作为快捷入口 |

不能因页面在 Mac 的 localhost 上可用，就认为手机的 HTTP 地址也有相同 API。若以后增加 HTTPS，仍须实际实现并验证权限、用户手势、离线缓存等行为；HTTPS 本身不会赋予后台采集能力。

## 加密范围

当前同步使用**应用层内容加密**，不是 HTTPS。文本、OCR、来源应用、文件路径、缩略图封装在 AES-256-GCM 密文中，原图接口返回加密字节。以下内容不在这个加密范围内：

- HTTP 页面与脚本、请求头中的鉴权 token。
- 记录元数据：`id`、`kind`、`ts`、`pinned`、`img`，以及 `/api/info` 信息。
- Mac 本地 SQLite、图片文件、iCloud 导出的 JSON 和图片。
- 浏览器 `localStorage` 中保存的配对码。

六位配对码只有 100 万种组合；HTTP 传输的 token 可用于离线枚举，页面和脚本也没有 TLS 保护。现有 401 限速只限制在线尝试，不能抵御离线枚举或主动网络篡改。因此不能将当前实现描述为「抓包只能看到乱码」或「全部加密存储」；仅在可信局域网使用。

## HTTP 协议

实现入口：[WebSyncServer.swift](../Sources/PasteHistory/Infrastructure/Sync/WebSyncServer.swift) 和 [WebSyncPage.swift](../Sources/PasteHistory/Presentation/Sync/WebSyncPage.swift)。修改任一端需同时核对另一端。

| 参数 | 值 |
| --- | --- |
| 配对码 | 六位十进制字符串，保留前导零 |
| 请求头 | `X-Pair-Token: SHA256(UTF8(pairCode))`，小写十六进制 |
| 内容密钥 | HKDF-SHA256，输入为配对码 UTF-8，输出 32 字节 |
| HKDF salt | `PasteHistory-Pairing-v1` 的 UTF-8 |
| HKDF info | `clip-payload` 的 UTF-8 |
| 密文结构 | 12 字节 nonce + ciphertext + 16 字节 GCM tag |
| JSON 中的密文 | 上述组合字节的 Base64 |

| 路由 | 鉴权 | 返回 / 输入 |
| --- | --- | --- |
| `/`、`/index.html` | 无 | 手机页面 |
| `/manifest.json`、`/apple-touch-icon.png`、`/icon.png` | 无 | 主屏资源；`/favicon.ico` 返回 204 |
| `GET /api/info` | 需要 | Mac 名称、协议版本、加密标记和记录总数 |
| `GET /api/clips` | 需要 | `{"clips":[...]}`，每条包含明文元数据和 Base64 `payload` |
| `GET /api/image/<name>.png` | 需要 | 原始组合密文字节，**不做 Base64** |
| `POST /api/clips` | 需要 | `{"payload":"<base64>"}`；网页内部明文为 `{"text":"…","kind":"text","app":"…"}` |

下发记录解密后的对象可能包含 `text`、`ocr`、`paths`、`app`、`thumb`；缺省字段可不存在，`thumb` 本身是 PNG 的 Base64。HTTP 状态包括 401（鉴权失败）、429（限速）、400（上传外层 JSON 或密文无效）和 404（未知路由或图片不存在）。

网络路由、加解密及独立 SQLite 读连接运行在 `com.verdent.pastehistory.websync` 队列，不能同步等待 MainActor。上传解密后异步交给主队列入库；**200 只表示请求已被接收并排队，不证明内容已有效落库**。端到端验证应再次读取，确认测试记录出现。

60 秒窗口内累积 10 次鉴权失败后返回 429；成功鉴权会清空失败记录。此状态由整个服务共享，不按客户端 IP 隔离。

## iCloud 文件协议

实现入口：[iCloudSync.swift](../Sources/PasteHistory/Infrastructure/Sync/iCloudSync.swift)。默认启用，目录不可用时不激活；菜单可开关。

```text
PasteHistory/
├── clips/<uuid>.json
├── tombstones/<uuid>.json
└── images/<内容指纹>.png
```

记录文件是信封对象，包含来源 `machine` 和 `clip`；删除信封使用 `deletedId`，清空操作另有 `clearAll`。确定性文件名避免同一记录产生多份文件，但不应据此承诺任意并发修改无冲突。

启动时导入，通过 `NSMetadataQuery` 监听变化，每 60 秒及打开面板时对账。首次启用导出存量；OCR 随记录同步，图片文件另行复制。优先使用可用的 ubiquity 容器，否则尝试 `~/Library/Mobile Documents/com~apple~CloudDocs/PasteHistory/`。

删除会移除记录文件并写墓碑。停用 iCloud 时 `--purge-ids` 无法清理远端；`--restore-images` 依赖活动同步目录和已经可读的远端原图。文件路径记录同步的是路径，不包含该路径对应的任意文件本体。

## 连接排障

1. 确认 Mac 上 PasteHistory 正在运行、Mac 未睡眠，手机能访问面板显示的地址。地址自动探测目前只检查 `en0` / `en1` 的 IPv4。
2. 检查两端网络可互访、路由器未启用设备隔离，以及手机本地网络权限和 Mac 防火墙放行情况。
3. 配对失效则使用当前二维码；429 时等待失败窗口过去再尝试，避免反复刷新请求。
4. 在 Mac 检查服务和图标可达：

   ```sh
   curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8377/
   curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8377/apple-touch-icon.png
   ```

本机 200 只说明本地可达，不证明手机网络、配对或上传入库正常。端口占用时查看配对面板提示；睡眠唤醒会尝试重启监听。

## 加密自测

改动网页或服务端加密实现后必做。当前仓库没有独立的 Node 加密测试脚本，应从实际 `WebSyncPage.swift` 提取回退实现，避免手写另一份算法来验证自身。

1. 用 Node 内置 `crypto.createHash` / `createHmac` / `hkdfSync` 对照 SHA-256、HMAC 和 HKDF，包含前导零配对码及 Unicode 文本。
2. AES 使用 FIPS-197 已知向量；GCM 使用 NIST 向量，再与 `createCipheriv('aes-256-gcm')` / 对应解密器双向交叉验证。
3. 覆盖空内容、16 字节整块、30 字节非整块、长文本和篡改 tag；修改密文或 tag 必须无法通过认证。长文本还要检查分块 Base64，避免参数数量上限。
4. 在隔离测试数据下，用当前配对码验证 `GET /api/clips` 中的每条内容和原图解密，再 `POST /api/clips` 上传合成文本，并轮询确认落库；不能只断言 200。
5. 用手机实际 HTTP 地址验证纯 JS 回退、粘贴框、复制失败回退及重新配对。

必要时可在本机用 `defaults read com.verdent.pastehistory webSyncPairCode` 读取配对码。它是访问凭据，不要粘进测试报告、日志或 PR。对真实服务做上传测试会创建历史并可能传播到 iCloud，优先使用隔离数据。
