import AppKit
import Foundation
import Vision

/// 图片索引服务：后台用 Vision OCR 识别图片文字，写回 SQLite 搜索列，
/// 让"截图里的文字"也能被搜到。同一张图在其他设备同步后不会重复识别。
@MainActor
final class OCRIndexer {
    static let shared = OCRIndexer()

    private let queue = DispatchQueue(label: "com.verdent.pastehistory.ocr", qos: .utility)
    private var inFlight = Set<UUID>()

    /// clip.ocrText == nil 时执行；完成后回调更新后的记录
    /// .image 识别 images 目录里的图；.files 里首个图片文件（如微信复制的 jpg）直接读原路径
    func indexIfNeeded(_ clip: ClipItem, completion: @escaping (ClipItem) -> Void) {
        guard clip.ocrText == nil, !inFlight.contains(clip.id) else { return }
        let imageURL: URL
        switch clip.kind {
        case .image:
            guard let name = clip.imageFile, !name.isEmpty else { return }
            imageURL = ClipStore.shared.imagesDirectory.appendingPathComponent(name)
        case .files:
            guard let path = clip.firstImageFilePath,
                  FileManager.default.fileExists(atPath: path) else { return }
            imageURL = URL(fileURLWithPath: path)
        case .text:
            return
        }
        inFlight.insert(clip.id)

        queue.async { [weak self] in
            let result = Self.analyze(imageURL: imageURL)
            Task { @MainActor in
                guard let self else { return }
                self.inFlight.remove(clip.id)
                var updated = clip
                updated.ocrText = result.text ?? ""
                ClipStore.shared.syncDatabase.updateOCR(id: clip.id,
                                                        ocrText: result.text ?? "",
                                                        sceneLabels: result.labels)
                completion(updated)
            }
        }
    }

    struct AnalyzeResult {
        var text: String?
        var labels: [String]
    }

    /// 文字识别（.accurate 支持中文；.fast 只支持英文等少数字符集）+ 场景分类标签
    static func analyze(imageURL: URL) -> AnalyzeResult {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return AnalyzeResult(text: nil, labels: [])
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // 1) 文字：accurate 模式 + 简繁中文 + 英文
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        textRequest.usesLanguageCorrection = false

        // 2) 场景分类：本地语义标签（screenshot / receipt / document 等）
        let classifyRequest = VNClassifyImageRequest()

        var text: String?
        var labels: [String] = []
        do {
            try handler.perform([textRequest, classifyRequest])

            let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            text = joined.isEmpty ? nil : joined

            labels = (classifyRequest.results ?? [])
                .filter { $0.confidence > 0.25 }
                .prefix(4)
                .map { $0.identifier }
        } catch {
            NSLog("[PasteHistory] 图片分析失败: \(error.localizedDescription)")
        }
        return AnalyzeResult(text: text, labels: labels)
    }
}
