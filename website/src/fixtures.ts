import type { Clip } from "./store";
const base = import.meta.env.BASE_URL;
export const sampleImage = `${base}sample-lake.jpg`;
export const sampleLanguages = [
  {
    code: "zh-Hans",
    label: "简体中文",
    text: "慢一点，灵感会追上来。\n给生活留一点空白。",
    image: "山野来信 · 布莱埃斯湖.jpg",
    file: "秋日灵感.fig",
  },
  {
    code: "en",
    label: "English",
    text: "Leave a little room for wonder.\nSave the thought. Find it when you need it.",
    image: "A quiet morning · Lake Braies.jpg",
    file: "Autumn inspiration.fig",
  },
  {
    code: "zh-Hant",
    label: "繁體中文",
    text: "把靈感收好，再慢慢展開。\n複製過的，隨時找回。",
    image: "山野來信 · 布萊埃斯湖.jpg",
    file: "秋日靈感.fig",
  },
  {
    code: "ja",
    label: "日本語",
    text: "ひらめきを、そっと残す。\nコピーしたものを、いつでも見つけよう。",
    image: "静かな朝 · ブラーイエス湖.jpg",
    file: "秋のアイデア.fig",
  },
  {
    code: "ko",
    label: "한국어",
    text: "떠오른 생각을 잠시 담아 두세요.\n복사한 내용을 언제든 다시 찾아보세요.",
    image: "고요한 아침 · 브라이에스 호수.jpg",
    file: "가을의 영감.fig",
  },
] as const;
export type SampleLanguage = (typeof sampleLanguages)[number]["code"];
export function initialClips(): Clip[] {
  const now = Date.now();
  const records: Omit<Clip, "id" | "created" | "pinned">[] = [
    {
      kind: "text",
      text: "今天也有好灵感。\n复制过的，随时找回。",
      source: "备忘录",
      lang: "zh-Hans",
    },
    {
      kind: "image",
      text: sampleLanguages[0].image,
      image: sampleImage,
      source: "照片",
      lang: "zh-Hans",
    },
    {
      kind: "text",
      text: sampleLanguages[1].text,
      source: "Safari",
      lang: "en",
    },
    {
      kind: "text",
      text: sampleLanguages[2].text,
      source: "備忘錄",
      lang: "zh-Hant",
    },
    { kind: "text", text: sampleLanguages[3].text, source: "メモ", lang: "ja" },
    {
      kind: "file",
      text: "灵感笔记.pdf",
      source: "访达",
      paths: ["/Users/demo/Documents/灵感笔记.pdf"],
      lang: "zh-Hans",
    },
    { kind: "text", text: sampleLanguages[4].text, source: "메모", lang: "ko" },
    {
      kind: "text",
      text: "周五 15:00\n聊聊下一个让人心动的想法。",
      source: "信息",
      lang: "zh-Hans",
    },
    {
      kind: "text",
      text: "Small ideas deserve a place to grow.",
      source: "Notes",
      lang: "en",
    },
    {
      kind: "text",
      text: "明天的清單：散步、閱讀、把想法變成作品。",
      source: "備忘錄",
      lang: "zh-Hant",
    },
    {
      kind: "text",
      text: "明日の予定：散歩、読書、アイデアを形にする。",
      source: "メモ",
      lang: "ja",
    },
    {
      kind: "text",
      text: "내일 할 일: 산책, 독서, 그리고 아이디어를 현실로 만들기.",
      source: "메모",
      lang: "ko",
    },
  ];
  return records.map((c, i) => ({
    ...c,
    id: `sample-${i}`,
    created: now - i * 180000,
    pinned: false,
  }));
}
