import { locale, t } from "./i18n";
import type { Clip } from "./store";
const base = import.meta.env.BASE_URL;
export const sampleImage = `${base}sample-lake.jpg`;
export const sampleLanguages = [
  {
    code: "zh-Hans",
    label: "简体中文",
    text: "给生活留一点空白。",
    image: "山野来信 · 布莱埃斯湖.jpg",
  },
  {
    code: "en",
    label: "English",
    text: "Leave room for wonder.",
    image: "A quiet morning · Lake Braies.jpg",
  },
  {
    code: "zh-Hant",
    label: "繁體中文",
    text: "把靈感收好。",
    image: "山野來信 · 布萊埃斯湖.jpg",
  },
  {
    code: "ja",
    label: "日本語",
    text: "ひらめきを、そっと残す。",
    image: "静かな朝 · ブラーイエス湖.jpg",
  },
  {
    code: "ko",
    label: "한국어",
    text: "떠오른 생각을 담아 두세요.",
    image: "고요한 아침 · 브라이에스 호수.jpg",
  },
] as const;
export type SampleLanguage = (typeof sampleLanguages)[number]["code"];
export function initialClips(): Clip[] {
  const now = Date.now();
  const sample = sampleLanguages.find((language) => language.code === locale)!;
  const text = (
    value: string,
    source = t("备忘录"),
  ): Omit<Clip, "id" | "created" | "pinned"> => ({
    kind: "text",
    text: value,
    source,
    lang: locale,
  });
  const records: Omit<Clip, "id" | "created" | "pinned">[] = [
    text(t("今天也有好灵感。\n复制过的，随时找回。")),
    {
      kind: "image",
      text: sample.image,
      image: sampleImage,
      source: t("照片"),
      lang: locale,
    },
    text(sample.text, "Safari"),
    text(t("把灵感收好，再慢慢展开。")),
    text(t("给生活留一点空白。")),
    {
      kind: "file",
      text: t("灵感笔记.pdf"),
      source: t("访达"),
      paths: [`/Users/demo/Documents/${t("灵感笔记.pdf")}`],
      lang: locale,
    },
    text(t("复制过的，随时找回。")),
    text(t("周五 15:00\n聊聊下一个让人心动的想法。"), t("信息")),
    text(t("小小的想法，也值得慢慢长大。")),
    text(t("明天的清单：散步、阅读、把想法变成作品。")),
    text(sample.text),
    text(t("给生活留一点空白。")),
  ];
  return records.map((c, i) => ({
    ...c,
    id: `sample-${i}`,
    created: now - i * 180000,
    pinned: false,
  }));
}
