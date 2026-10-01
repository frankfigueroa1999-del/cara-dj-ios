import SwiftUI
import UIKit
import ImageIO
import CoreImage

/// Downloads cover art once, shrinks it to the size it's shown at, and keeps it in memory,
/// so lists scroll smoothly and covers appear instantly the second time.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    private func key(_ url: String, _ px: Int) -> String { "\(px)|" + url }

    func cached(_ url: String, px: Int) -> UIImage? {
        cache.object(forKey: key(url, px) as NSString)
    }

    private func running(_ k: String) -> Task<UIImage?, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return inflight[k]
    }

    private func setRunning(_ k: String, _ t: Task<UIImage?, Never>?) {
        lock.lock()
        inflight[k] = t
        lock.unlock()
    }

    func load(_ url: String, px: Int) async -> UIImage? {
        let k = key(url, px)
        if let img = cache.object(forKey: k as NSString) { return img }
        if let t = running(k) { return await t.value }
        guard let u = URL(string: url) else { return nil }
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = await fetchData(u, timeout: 15) else { return nil }
            return ImageCache.downsample(data, px: px)
        }
        setRunning(k, task)
        let img = await task.value
        setRunning(k, nil)
        if let img = img {
            let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
            cache.setObject(img, forKey: k as NSString, cost: cost)
        }
        return img
    }

    static func downsample(_ data: Data, px: Int) -> UIImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let thumb = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: px,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumb) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

/// A cover / artist picture with a soft placeholder, that fades in when it arrives.
struct Artwork: View {
    let url: String?
    var px: Int
    var corner: CGFloat
    var circle: Bool
    @State private var image: UIImage?
    @State private var shownURL: String?

    init(_ url: String?, px: Int = 300, corner: CGFloat = 8, circle: Bool = false) {
        self.url = url
        self.px = px
        self.corner = corner
        self.circle = circle
        var first: UIImage? = nil
        if let u = url, !u.isEmpty { first = ImageCache.shared.cached(u, px: px) }
        _image = State(initialValue: first)
        _shownURL = State(initialValue: first == nil ? nil : url)
    }

    private var shape: AnyShape {
        circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill().transition(.opacity)
                } else {
                    GeometryReader { g in
                        Image(systemName: circle ? "music.mic" : "music.note")
                            .font(.system(size: max(10, min(g.size.width, g.size.height) * 0.34), weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: g.size.width, height: g.size.height)
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.white.opacity(0.06), lineWidth: 0.5) }
            .task(id: url ?? "") { await load() }
    }

    private func load() async {
        guard let u = url, !u.isEmpty else {
            image = nil
            shownURL = nil
            return
        }
        if shownURL == u && image != nil { return }
        if let c = ImageCache.shared.cached(u, px: px) {
            image = c
            shownURL = u
            return
        }
        let img = await ImageCache.shared.load(u, px: px)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.25)) {
            image = img
            shownURL = u
        }
    }
}

/// The colours behind the big player: a blurred, tiny copy of the cover, plus how bright it is.
enum ArtColors {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func backdrop(from img: UIImage) async -> (image: UIImage?, brightness: Double) {
        await Task.detached(priority: .userInitiated) { () -> (image: UIImage?, brightness: Double) in
            guard let cg = img.cgImage else { return (nil, 0.4) }
            let ci = CIImage(cgImage: cg)
            let w = max(ci.extent.width, 1)
            let scale = 40.0 / w
            let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: small.extent)
            guard let out = ArtColors.context.createCGImage(blurred, from: small.extent) else { return (nil, 0.4) }
            return (UIImage(cgImage: out), ArtColors.brightness(out))
        }.value
    }

    /// 0 = black, 1 = white.
    static func brightness(_ cg: CGImage) -> Double {
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// The cover's average colour, for tinting cards.
    static func average(_ img: UIImage) -> Color {
        guard let cg = img.cgImage else { return Color(white: 0.2) }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        return Color(red: Double(px[0]) / 255 * 0.8, green: Double(px[1]) / 255 * 0.8, blue: Double(px[2]) / 255 * 0.8)
    }
}
