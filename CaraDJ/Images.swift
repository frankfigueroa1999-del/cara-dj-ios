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
        if url == Silence.logo { return logo(px) }
        return cache.object(forKey: key(url, px) as NSString)
    }

    /// Cara's own artwork, drawn on the phone (no download).
    private func logo(_ px: Int) -> UIImage {
        let k = key(Silence.logo, px) as NSString
        if let img = cache.object(forKey: k) { return img }
        let img = CaraArt.image(px: px)
        cache.setObject(img, forKey: k)
        return img
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
        if url == Silence.logo { return logo(px) }
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
            .fill(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill().transition(.opacity)
                } else {
                    GeometryReader { g in
                        Image(systemName: circle ? "music.mic" : "music.note")
                            .font(.system(size: max(10, min(g.size.width, g.size.height) * 0.32), weight: .light))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .frame(width: g.size.width, height: g.size.height)
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.white.opacity(0.09), lineWidth: 0.5) }
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

/// Cara's "cover" while she's on the air: the station's waveform logo, glowing on her colours.
enum CaraArt {
    private static let bars: [CGFloat] = [0.35, 0.65, 1.0, 0.55, 0.85, 0.45, 0.7]

    static func image(px: Int) -> UIImage {
        let side = CGFloat(min(max(px, 64), 1200))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(red: 0.98, green: 0.20, blue: 0.36, alpha: 1).cgColor,
                          UIColor(red: 0.42, green: 0.15, blue: 0.62, alpha: 1).cgColor,
                          UIColor(red: 0.07, green: 0.04, blue: 0.16, alpha: 1).cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.55, 1]
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
                cg.drawLinearGradient(g, start: CGPoint.zero, end: CGPoint(x: side, y: side), options: [])
            }
            // a soft glow behind the logo
            let glow = [UIColor(white: 1, alpha: 0.22).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let glowStops: [CGFloat] = [0, 1]
            if let g = CGGradient(colorsSpace: space, colors: glow, locations: glowStops) {
                let c = CGPoint(x: side / 2, y: side / 2)
                cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: side * 0.42, options: [])
            }
            let count = CGFloat(bars.count)
            let width = side * 0.46
            let gap = width / (count * 2 - 1)
            let tall = side * 0.32
            let x0 = (side - width) / 2
            UIColor.white.setFill()
            for (i, b) in bars.enumerated() {
                let h = tall * b
                let r = CGRect(x: x0 + CGFloat(i) * gap * 2, y: side / 2 - h / 2, width: gap, height: h)
                UIBezierPath(roundedRect: r, cornerRadius: gap / 2).fill()
            }
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

    /// A small, very soft and slightly richer copy of a cover, made to be stretched across a whole page,
    /// plus how bright it is (bright covers get darkened more, so white text always reads).
    static func ambient(from img: UIImage) async -> (image: UIImage, brightness: Double)? {
        await Task.detached(priority: .utility) { () -> (image: UIImage, brightness: Double)? in
            guard let cg = img.cgImage else { return nil }
            let ci = CIImage(cgImage: cg)
            let w = max(ci.extent.width, 1)
            let scale = 96.0 / w
            let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let rich = small.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
            let soft = rich.clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: small.extent)
            guard let out = ArtColors.context.createCGImage(soft, from: small.extent) else { return nil }
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
