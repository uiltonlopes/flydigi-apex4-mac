// Turns a GIF/PNG/JPEG into LVGL frames for the LCD, using ImageIO + CoreGraphics.

import Foundation
import ImageIO
import CoreGraphics
import FlydigiKit

/// Which part of the source lands on the 160 × 80 screen: a rectangle in source pixels (it may extend past
/// the image, the rest is black). `nil` means aspect-fill.
public struct ScreenCrop: Sendable, Equatable {
    public var x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public enum ImageLoader {
    /// Decodes every frame (up to `Screen.maxFrames`), scales to 160×80 (aspect-fill, centred) and encodes.
    public static func frames(url: URL, maxFrames: Int = Screen.maxFrames) throws -> [[UInt8]] {
        let d = try decode(url: url)
        return frames(images: pick(d.images, max: maxFrames), crop: nil)
    }

    /// Decoded source frames with their delays in seconds (stills: one frame, delay 0).
    public static func decode(url: URL) throws -> (images: [CGImage], delays: [Double]) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw TransportError.io("cannot read \(url.path)") }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { throw TransportError.io("no image frames in \(url.path)") }
        var images: [CGImage] = [], delays: [Double] = []
        for i in 0..<count {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { throw TransportError.io("frame \(i) undecodable") }
            images.append(img)
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            delays.append(count > 1 ? ((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1) : 0)
        }
        return (images, delays)
    }

    /// Evenly thins a frame list down to `max` frames (keeps first and last).
    public static func pick(_ images: [CGImage], max: Int) -> [CGImage] {
        guard images.count > max, max > 0 else { return images }
        return (0..<max).map { images[Int((Double($0) * Double(images.count - 1) / Double(max - 1)).rounded())] }
    }

    /// Encodes decoded frames with an optional crop (source pixels → whole screen).
    public static func frames(images: [CGImage], crop: ScreenCrop?) -> [[UInt8]] {
        images.map { Screen.encodeFrame(rgb: rgb8($0, width: Screen.width, height: Screen.height, crop: crop)) }
    }

    /// Preview of one frame exactly as the screen will show it (160 × 80, RGB565-quantised).
    public static func preview(_ img: CGImage, crop: ScreenCrop?) -> CGImage? {
        let rgb = rgb8(img, width: Screen.width, height: Screen.height, crop: crop)
        var q = [UInt8](repeating: 255, count: Screen.width * Screen.height * 4)
        for i in 0..<(Screen.width * Screen.height) {
            q[i * 4] = rgb[i * 3] & 0xF8; q[i * 4 + 1] = rgb[i * 3 + 1] & 0xFC; q[i * 4 + 2] = rgb[i * 3 + 2] & 0xF8
        }
        guard let provider = CGDataProvider(data: Data(q) as CFData) else { return nil }
        return CGImage(width: Screen.width, height: Screen.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Screen.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func rgb8(_ img: CGImage, width w: Int, height h: Int, crop: ScreenCrop? = nil) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
        if let c = crop, c.width > 0, c.height > 0 {
            // Map the crop rectangle (source pixels, top-left origin) onto the whole canvas.
            let k = CGFloat(w) / c.width
            let dw = CGFloat(img.width) * k, dh = CGFloat(img.height) * k
            let x = -c.x * k
            let yTop = -c.y * k                                   // top-left origin → flip for CoreGraphics
            ctx.draw(img, in: CGRect(x: x, y: CGFloat(h) - yTop - dh, width: dw, height: dh))
        } else {
            // aspect-fill
            let scale = max(CGFloat(w) / CGFloat(img.width), CGFloat(h) / CGFloat(img.height))
            let dw = CGFloat(img.width) * scale, dh = CGFloat(img.height) * scale
            ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
        }
        var rgb = [UInt8](); rgb.reserveCapacity(w * h * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) { rgb.append(rgba[i]); rgb.append(rgba[i + 1]); rgb.append(rgba[i + 2]) }
        return rgb
    }
}
