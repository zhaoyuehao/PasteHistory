import AppKit
import ImageIO

/// Read-only image decoding/cache service. Receives its storage location from
/// composition; knows nothing about windows, selection, typography or motion.
@MainActor
final class PreviewMediaLoader {
    struct Asset {
        let image: NSImage?
        let pixels: CGSize?
        let bytes: Int?
    }
    private let imagesDirectory: URL
    private let cache = NSCache<NSString, NSImage>()
    init(imagesDirectory: URL) {
        self.imagesDirectory = imagesDirectory
        cache.countLimit = 16
        cache.totalCostLimit = 64 * 1024 * 1024
    }
    func url(for item: ClipItem) -> URL? {
        if item.kind == .image, let name = item.imageFile {
            return imagesDirectory.appendingPathComponent(name)
        }
        return item.firstImageFilePath.map { URL(fileURLWithPath: $0) }
    }
    func cachedImage(at url: URL) -> NSImage? { cache.object(forKey: url.path as NSString) }

    func load(_ url: URL, maxPixel: CGFloat) async -> Asset? {
        guard !Task.isCancelled else { return nil }
        let cached = cachedImage(at: url)
        if cached == nil {
            // Coalesce navigation before beginning non-cancellable ImageIO work.
            do { try await Task.sleep(for: .milliseconds(55)) } catch { return nil }
        }
        guard !Task.isCancelled else { return nil }
        let asset = await Task.detached(priority: .userInitiated) {
            Self.read(url, maxPixel: maxPixel, decode: cached == nil)
        }.value
        guard !Task.isCancelled else { return nil }
        if let image = asset.image {
            cache.setObject(image, forKey: url.path as NSString,
                            cost: Int(image.size.width * image.size.height * 4))
        }
        return Asset(image: cached ?? asset.image, pixels: asset.pixels, bytes: asset.bytes)
    }
    nonisolated private static func read(_ url: URL, maxPixel: CGFloat, decode: Bool) -> Asset {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return Asset(image: nil, pixels: nil, bytes: bytes)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixels: CGSize?
        if let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat {
            pixels = CGSize(width: width, height: height)
        } else { pixels = nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        let cg = decode ? CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) : nil
        let image = cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        return Asset(image: image, pixels: pixels, bytes: bytes)
    }
}
