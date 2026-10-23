import Foundation

/// Display policy only. OCR remains in ClipItem/search storage and is never
/// substituted for the visual contents of an image card.
struct ClipPresentation {
    let item: ClipItem
    var imageFirst: Bool { item.kind == .image || item.firstImageFilePath != nil }
    var compactTitle: String { imageFirst ? L10n.image : item.summary }
    var imageDetails: String {
        let caption = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ocr = item.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ocr.isEmpty, ocr != caption else { return caption }
        let recognized = L10n.value("识别文字", "識別文字", "Recognized text") + "\n" + ocr
        return caption.isEmpty ? recognized : caption + "\n\n" + recognized
    }
}
