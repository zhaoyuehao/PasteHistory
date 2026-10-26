import type { Clip } from "./store";
const base = import.meta.env.BASE_URL;
export const sampleImage = `${base}sample-postcard.svg`;
export function initialClips(): Clip[] {
  const now = Date.now();
  const records: Omit<Clip, "id" | "created" | "pinned">[] = [
    { kind: "text", text: "今天也有好灵感。", source: "备忘录" },
    {
      kind: "image",
      text: "山野来信 · 秋日明信片",
      image: sampleImage,
      ocr: "山野来信 慢一点，灵感会追上来。",
      source: "照片",
    },
    {
      kind: "text",
      text: "好的工具，应该像一阵风。\n需要时出现，离开时安静。",
      source: "Safari",
    },
    {
      kind: "text",
      text: "周五 15:00\n聊聊下一个让人心动的想法。",
      source: "信息",
    },
    {
      kind: "text",
      text: "把灵感收好，再慢慢展开。\nKeep a little room for wonder.",
      source: "备忘录",
    },
    { kind: "file", text: "灵感笔记.pdf", source: "访达" },
    {
      kind: "text",
      text: "山间的绿，纸上的暖。\n#536D60 · #EEE9DC · #C89E62",
      source: "Safari",
    },
    { kind: "text", text: "今天也有值得记住的小事。", source: "日记" },
    { kind: "text", text: "一棵树，收下每一次复制。", source: "备忘录" },
    {
      kind: "text",
      text: 'const idea = "something wonderful";',
      source: "编辑器",
    },
    {
      kind: "text",
      text: "https://github.com/zhaoyuehao/PasteHistory",
      source: "Safari",
    },
    {
      kind: "text",
      text: "明天的清单：\n散步、读书、把想法变成作品。",
      source: "备忘录",
    },
  ];
  return records.map((c, i) => ({
    ...c,
    id: `sample-${i}`,
    created: now - i * 180000,
    pinned: false,
  }));
}

// The first visit introduces only the three supported clipboard kinds.
export function welcomeClips(): Clip[] {
  const clips = initialClips();
  return [clips[0], clips[1], clips[5]];
}
