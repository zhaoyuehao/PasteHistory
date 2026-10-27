export const locales = [
  ["en", "English"],
  ["zh-Hans", "简体中文"],
  ["zh-Hant", "繁體中文"],
  ["ja", "日本語"],
  ["ko", "한국어"],
] as const;
export type Locale = (typeof locales)[number][0];
export function browserLocale(): Locale {
  const languages =
    typeof navigator === "undefined"
      ? ["en"]
      : (navigator.languages ?? [navigator.language]);
  for (const language of languages) {
    const tag = language.toLowerCase();
    if (tag.startsWith("zh"))
      return /hant|tw|hk|mo/.test(tag) ? "zh-Hant" : "zh-Hans";
    if (tag.startsWith("ja")) return "ja";
    if (tag.startsWith("ko")) return "ko";
    if (tag.startsWith("en")) return "en";
  }
  return "en";
}
const localeStorageKey = "pastehistory-locale";
function isLocale(value: unknown): value is Locale {
  return locales.some(([code]) => code === value);
}
export function preferredLocale(): Locale {
  try {
    const saved = localStorage.getItem(localeStorageKey);
    if (isLocale(saved)) return saved;
  } catch {
    // Storage can be unavailable; browser detection still works.
  }
  return browserLocale();
}
export let locale: Locale = preferredLocale();
export function setLocale(value: string) {
  if (!isLocale(value)) return;
  locale = value;
  document.documentElement.lang = locale;
  try {
    localStorage.setItem(localeStorageKey, locale);
  } catch {
    // Keep the current page usable when persistence is denied.
  }
}
// Simplified Chinese keys, followed by English, Traditional Chinese, Japanese and Korean.
const messages: Record<string, readonly [string, string, string, string]> = {
  复制: ["Copy", "複製", "コピー", "복사"],
  复制文字: ["Copy text", "複製文字", "テキストをコピー", "텍스트 복사"],
  复制图片: ["Copy image", "複製圖片", "画像をコピー", "이미지 복사"],
  "正在获取下载…": [
    "Getting download…",
    "正在取得下載…",
    "ダウンロードを取得中…",
    "다운로드 확인 중…",
  ],
  下载暂不可用: [
    "Download unavailable",
    "下載暫不可用",
    "ダウンロードできません",
    "다운로드를 사용할 수 없어요",
  ],
  "无法检查更新，将下载已知版本": [
    "Cannot check for updates; downloading the last known version",
    "無法檢查更新，將下載已知版本",
    "更新を確認できないため、取得済みのバージョンをダウンロードします",
    "업데이트를 확인할 수 없어 마지막으로 확인된 버전을 다운로드합니다",
  ],
  复制样例: ["Copy samples", "複製範例", "コピーのサンプル", "복사 예제"],
  复制到树: ["Copy to tree", "複製到樹", "木にコピー", "나무에 복사"],
  "拖到这里，或直接粘贴。": [
    "Drop or paste here.",
    "拖到這裡，或直接貼上。",
    "ここにドロップ、または貼り付け。",
    "여기에 끌어오거나 붙여넣으세요.",
  ],
  选择: ["Select", "選擇", "選択", "선택"],
  粘贴: ["Paste", "貼上", "貼り付け", "붙여넣기"],
  打开许愿树: ["Open tree", "開啟許願樹", "木を開く", "나무 열기"],
  "复制过的，随时找回。": [
    "Everything you copy, ready when you need it.",
    "複製過的，隨時找回。",
    "コピーしたものを、いつでも。",
    "복사한 내용을 언제든 다시 찾아보세요.",
  ],
  语言: ["Language", "語言", "言語", "언어"],
  许愿树剪贴板: [
    "Clipboard tree",
    "許願樹剪貼簿",
    "クリップボードの木",
    "클립보드 나무",
  ],
  移动端剪贴板历史: [
    "Clipboard history on your phone",
    "手機上的剪貼簿歷史",
    "スマホのクリップボード履歴",
    "휴대폰 클립보드 기록",
  ],
  "自动保存你复制过的文字、图片和文件，随时搜索、复制，或拖到备忘录。": [
    "Keep copied text, images and files ready to search, copy or drag into Notes.",
    "保存複製過的文字、圖片和檔案，隨時搜尋、複製，或拖到備忘錄。",
    "コピーしたテキスト、画像、ファイルを保存し、検索、コピー、メモへドラッグできます。",
    "복사한 텍스트, 이미지, 파일을 저장해 검색하거나 복사하고 메모로 끌어올 수 있어요.",
  ],
  "点一下搜索，长按纸签拖到备忘录": [
    "Tap Search, or long-press a paper and drag it to Notes",
    "點一下搜尋，長按紙籤拖到備忘錄",
    "検索をタップ、または紙を長押ししてメモへドラッグ",
    "검색을 누르거나 종이를 길게 눌러 메모로 끌어오세요",
  ],
  "枝头暂时空了。": [
    "No clips on these branches.",
    "枝頭暫時空了。",
    "まだクリップがありません。",
    "아직 클립이 없어요.",
  ],
  "换个关键词，或复制一条新灵感。": [
    "Try another search, or copy a new idea.",
    "換個關鍵字，或複製一則新靈感。",
    "別の言葉で検索するか、新しいアイデアをコピー。",
    "다른 검색어를 쓰거나 새 아이디어를 복사해 보세요.",
  ],
  搜索剪贴板: [
    "Search clipboard",
    "搜尋剪貼簿",
    "クリップボードを検索",
    "클립보드 검색",
  ],
  搜索: ["Search", "搜尋", "検索", "검색"],
  "下载 PasteHistory": [
    "Download PasteHistory",
    "下載 PasteHistory",
    "PasteHistory をダウンロード",
    "PasteHistory 다운로드",
  ],
  "下载 Mac 版": [
    "Download for Mac",
    "下載 Mac 版",
    "Mac 版をダウンロード",
    "Mac용 다운로드",
  ],
  "预览版 · 未经 Apple 公证": [
    "Preview · Not notarized by Apple",
    "預覽版 · 未經 Apple 公證",
    "プレビュー版 · Apple 公証なし",
    "미리보기 버전 · Apple 공증 없음",
  ],
  素材浏览器: ["Copy samples", "複製範例", "コピーのサンプル", "복사 예제"],
  素材类型: ["Sample type", "範例類型", "サンプルの種類", "예제 유형"],
  文字: ["Text", "文字", "テキスト", "텍스트"],
  图片: ["Image", "圖片", "画像", "이미지"],
  文件: ["File", "檔案", "ファイル", "파일"],
  备忘录: ["Notes", "備忘錄", "メモ", "메모"],
  清空备忘录: ["Clear Notes", "清空備忘錄", "メモを消去", "메모 비우기"],
  备忘录内容: ["Note content", "備忘錄內容", "メモの内容", "메모 내용"],
  "粘贴目标 · 保留光标位置": [
    "Paste here · Cursor position kept",
    "貼上目標 · 保留游標位置",
    "貼り付け先 · カーソル位置を保持",
    "붙여넣기 대상 · 커서 위치 유지",
  ],
  下载次数: ["Downloads", "下載次數", "ダウンロード数", "다운로드 수"],
  "下载与 GitHub": [
    "Download and GitHub",
    "下載與 GitHub",
    "ダウンロードと GitHub",
    "다운로드 및 GitHub",
  ],
  预览: ["Preview", "預覽", "プレビュー", "미리보기"],
  纸签预览: ["Clip preview", "紙籤預覽", "紙札のプレビュー", "클립 미리보기"],
  常用快捷键: [
    "Keyboard shortcuts",
    "常用快捷鍵",
    "キーボードショートカット",
    "키보드 단축키",
  ],
  找回复制过的内容: [
    "Find what you copied",
    "找回複製過的內容",
    "コピーしたものを見つける",
    "복사한 내용을 찾아보세요",
  ],
  "按快捷键或点这里，打开许愿树": [
    "Press the shortcut or click here to open the tree",
    "按快捷鍵或點這裡，開啟許願樹",
    "ショートカットかクリックで木を開く",
    "단축키를 누르거나 여기를 클릭해 나무를 여세요",
  ],
  可复制的示例文字: [
    "Editable sample text",
    "可複製的範例文字",
    "コピーできるサンプルテキスト",
    "복사할 예제 텍스트",
  ],
  示例文件路径: [
    "Example file path",
    "範例檔案路徑",
    "サンプルのファイルパス",
    "예제 파일 경로",
  ],
  先写下一点灵感吧: [
    "Write a little inspiration first",
    "先寫下一點靈感吧",
    "まずはひらめきを書いてみましょう",
    "먼저 아이디어를 적어 보세요",
  ],
  已收藏到许愿树: [
    "Saved to the tree",
    "已收藏到許願樹",
    "木に保存しました",
    "나무에 저장했어요",
  ],
  手机同步: ["Phone Sync", "手機同步", "スマホ同期", "휴대폰 동기화"],
  "网页演示 · 未连接设备": [
    "Web demo · No device connected",
    "網頁示範 · 未連接裝置",
    "ウェブデモ · デバイス未接続",
    "웹 데모 · 연결된 기기 없음",
  ],
  "手机同步\n\nMac 版可以通过局域网与手机配对。网页体验不连接真实设备，也不生成配对二维码。":
    [
      "Phone Sync\n\nThe Mac app pairs with your phone over a local network. This web demo does not connect to devices or generate pairing codes.",
      "手機同步\n\nMac 版可透過區域網路與手機配對。網頁體驗不連接真實裝置，也不產生配對 QR Code。",
      "スマホ同期\n\nMac 版はローカルネットワークでスマホとペアリングできます。このデモではデバイス接続や QR コード生成は行いません。",
      "휴대폰 동기화\n\nMac 앱은 로컬 네트워크로 휴대폰과 페어링할 수 있습니다. 이 웹 데모는 실제 기기에 연결하거나 페어링 코드를 생성하지 않습니다.",
    ],
  "预置 OCR 示例文字": [
    "Preset OCR sample text",
    "預設 OCR 範例文字",
    "あらかじめ用意した OCR サンプル",
    "사전 설정 OCR 예제 텍스트",
  ],
  演示文件: ["Demo file", "示範檔案", "デモファイル", "데모 파일"],
  已粘贴到原输入位置: [
    "Pasted at the original cursor",
    "已貼到原輸入位置",
    "元の位置に貼り付けました",
    "원래 커서 위치에 붙여넣었어요",
  ],
  图片已放入备忘录: [
    "Image added to Notes",
    "圖片已放入備忘錄",
    "画像をメモに追加しました",
    "이미지를 메모에 추가했어요",
  ],
  已粘贴到备忘录: [
    "Pasted into Notes",
    "已貼到備忘錄",
    "メモに貼り付けました",
    "메모에 붙여넣었어요",
  ],
  "拖到备忘录后松手": [
    "Drag to Notes and release",
    "拖到備忘錄後放開",
    "メモまでドラッグして離します",
    "메모로 끌어온 뒤 놓으세요",
  ],
  图片无法显示: [
    "Image unavailable",
    "圖片無法顯示",
    "画像を表示できません",
    "이미지를 표시할 수 없어요",
  ],
  粘贴的图片: [
    "Pasted image",
    "貼上的圖片",
    "貼り付けた画像",
    "붙여넣은 이미지",
  ],
  本次粘贴: ["Pasted", "本次貼上", "貼り付け", "붙여넣기"],
  已复制到系统剪贴板: [
    "Copied to the system clipboard",
    "已複製到系統剪貼簿",
    "クリップボードにコピーしました",
    "시스템 클립보드에 복사했어요",
  ],
  "浏览器未允许复制；仍可粘贴到演示备忘录": [
    "Clipboard access was denied. You can still paste into demo Notes.",
    "瀏覽器未允許複製；仍可貼到示範備忘錄",
    "コピーが許可されませんでした。デモのメモには貼り付けられます。",
    "클립보드 접근이 거부되었지만 데모 메모에는 붙여넣을 수 있어요.",
  ],
  纸签已删除: ["Clip deleted", "紙籤已刪除", "削除しました", "삭제했어요"],
  "预览版，未经 Apple 公证。使用 Apple Development 签名，下载后可能受到 macOS 系统拦截。":
    [
      "Preview, not notarized by Apple. Signed with Apple Development; macOS may block the downloaded app.",
      "預覽版，未經 Apple 公證。使用 Apple Development 簽章，下載後可能受到 macOS 系統攔截。",
      "Apple 公証のないプレビュー版です。Apple Development で署名されていますが、macOS にブロックされる場合があります。",
      "Apple 공증을 받지 않은 미리보기 버전입니다. Apple Development로 서명되었으며 macOS에서 차단될 수 있습니다.",
    ],
  "解压后将 PasteHistory.app 放入「应用程序」。首次使用需在系统设置中允许辅助功能，才能粘贴到其他应用。":
    [
      "Unzip and move PasteHistory.app into Applications. Allow Accessibility in System Settings to paste into other apps.",
      "解壓後將 PasteHistory.app 放入「應用程式」。首次使用需在系統設定中允許輔助使用，才能貼到其他 App。",
      "展開した PasteHistory.app を「アプリケーション」に移動します。他のアプリに貼り付けるには、システム設定でアクセシビリティを許可してください。",
      "압축을 풀고 PasteHistory.app을 응용 프로그램 폴더로 옮기세요. 다른 앱에 붙여넣으려면 시스템 설정에서 손쉬운 사용 권한을 허용하세요.",
    ],
  "可拖入 PNG、JPEG、GIF、WebP、AVIF 或 BMP 图片": [
    "Drop PNG, JPEG, GIF, WebP, AVIF or BMP images",
    "可拖入 PNG、JPEG、GIF、WebP、AVIF 或 BMP 圖片",
    "PNG、JPEG、GIF、WebP、AVIF、BMP 画像に対応",
    "PNG, JPEG, GIF, WebP, AVIF, BMP 이미지를 지원해요",
  ],
  暂不可用: ["Unavailable", "暫不可用", "利用不可", "사용 불가"],
  "所有公开 Release 安装包累计下载": [
    "Total downloads of public release installers",
    "所有公開 Release 安裝檔累計下載",
    "公開リリースのインストーラ総ダウンロード数",
    "공개 릴리스 설치 파일의 총 다운로드 수",
  ],
  缓存数据: ["Cached data", "快取資料", "キャッシュ", "캐시 데이터"],
  "GitHub 数据暂不可用": [
    "GitHub data unavailable",
    "GitHub 資料暫不可用",
    "GitHub データを取得できません",
    "GitHub 데이터를 사용할 수 없어요",
  ],
  "原生 SceneKit 许愿树与五只小鸟": [
    "Native SceneKit tree with five birds",
    "原生 SceneKit 許願樹與五隻小鳥",
    "5 羽の鳥がいる SceneKit の木",
    "다섯 마리 새가 있는 SceneKit 나무",
  ],
  照片: ["Photos", "照片", "写真", "사진"],
  访达: ["Finder", "Finder", "Finder", "Finder"],
  信息: ["Messages", "訊息", "メッセージ", "메시지"],
  "今天也有好灵感。\n复制过的，随时找回。": [
    "A little inspiration for today.\nEverything you copy, ready when you need it.",
    "今天也有好靈感。\n複製過的，隨時找回。",
    "今日も、ひらめきをひとつ。\nコピーしたものを、いつでも。",
    "오늘도 좋은 아이디어.\n복사한 내용을 언제든 다시 찾아보세요.",
  ],
  "周五 15:00\n聊聊下一个让人心动的想法。": [
    "Friday, 3 PM\nLet's talk about our next exciting idea.",
    "週五 15:00\n聊聊下一個讓人心動的想法。",
    "金曜 15:00\n次のわくわくするアイデアを話そう。",
    "금요일 오후 3시\n다음 설레는 아이디어를 이야기해요.",
  ],
  "灵感笔记.pdf": [
    "Ideas.pdf",
    "靈感筆記.pdf",
    "アイデアノート.pdf",
    "아이디어 노트.pdf",
  ],
  "小小的想法，也值得慢慢长大。": [
    "Small ideas deserve a place to grow.",
    "小小的想法，也值得慢慢長大。",
    "小さなアイデアも、ゆっくり育てよう。",
    "작은 아이디어도 자랄 공간이 필요해요.",
  ],
  "明天的清单：散步、阅读、把想法变成作品。": [
    "Tomorrow: a walk, a book, and an idea brought to life.",
    "明天的清單：散步、閱讀、把想法變成作品。",
    "明日の予定：散歩、読書、アイデアを形にする。",
    "내일 할 일: 산책, 독서, 그리고 아이디어를 현실로 만들기.",
  ],
  "把灵感收好，再慢慢展开。": [
    "Keep the idea. Let it unfold.",
    "把靈感收好，再慢慢展開。",
    "ひらめきを残して、ゆっくり広げよう。",
    "아이디어를 간직하고 천천히 펼쳐 보세요.",
  ],
  "给生活留一点空白。": [
    "Leave a little room for wonder.",
    "給生活留一點空白。",
    "暮らしに、少しの余白を。",
    "일상에 작은 여백을 남겨 두세요.",
  ],
};
export function t(key: string): string {
  if (locale === "zh-Hans") return key;
  return messages[key]?.[{ en: 0, "zh-Hant": 1, ja: 2, ko: 3 }[locale]] ?? key;
}
// Bind only authored UI labels, never editor contents or clipboard records.
const textLabels = new Map<Text, string>();
const attributes = new Map<Element, Map<string, string>>();
export function bindLabels(root: Element) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode as Text;
    if (
      node.parentElement?.closest(
        "[contenteditable],textarea,#sample-content,#tree-stage,#preview-content",
      )
    )
      continue;
    if (messages[node.data.trim()]) textLabels.set(node, node.data);
  }
  for (const element of [root, ...root.querySelectorAll("*")]) {
    for (const name of ["aria-label", "data-placeholder", "title"]) {
      const value = element.getAttribute(name);
      if (!value || !messages[value]) continue;
      const labels = attributes.get(element) ?? new Map<string, string>();
      labels.set(name, value);
      attributes.set(element, labels);
    }
  }
  refreshLabels();
}
export function refreshLabels() {
  for (const [node, key] of textLabels) {
    if (!node.isConnected) {
      textLabels.delete(node);
      continue;
    }
    node.data = key.replace(key.trim(), t(key.trim()));
  }
  for (const [element, labels] of attributes) {
    if (!element.isConnected) {
      attributes.delete(element);
      continue;
    }
    for (const [name, key] of labels) element.setAttribute(name, t(key));
  }
}
