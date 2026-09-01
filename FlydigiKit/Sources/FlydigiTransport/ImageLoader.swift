// Turns a GIF/PNG/JPEG into LVGL frames for the LCD, using ImageIO + CoreGraphics.

import Foundation
import ImageIO
import CoreGraphics
import FlydigiKit

public enum ImageLoader {
    /// Decodes every frame (up to `Screen.maxFrames`), scales to 160×80 (aspect-fill, centred) and encodes.
    public static func frames(url: URL, maxFrames: Int = Screen.maxFrames) throws -> [[UInt8]] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw TransportError.io("cannot read \(url.path)") }
        let count = min(CGImageSourceGetCount(src), maxFrames)
        guard count > 0 else { throw TransportError.io("no image frames in \(url.path)") }
        return try (0..<count).map { i in
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { throw TransportError.io("frame \(i) undecodable") }
            return Screen.encodeFrame(rgb: rgb8(img, width: Screen.width, height: Screen.height))
        }
    }

    /// Average frame delay in centiseconds (what the firmware's `freq` field expects), 0 for stills.
    public static func frameDelayCentiseconds(url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        let n = CGImageSourceGetCount(src); guard n > 1 else { return 0 }
        var total = 0.0
        for i in 0..<n {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        }
        return max(1, Int(total / Double(n) * 100))
    }

    static func rgb8(_ img: CGImage, width w: Int, height h: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
        // aspect-fill
        let scale = max(CGFloat(w) / CGFloat(img.width), CGFloat(h) / CGFloat(img.height))
        let dw = CGFloat(img.width) * scale, dh = CGFloat(img.height) * scale
        ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
        var rgb = [UInt8](); rgb.reserveCapacity(w * h * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) { rgb.append(rgba[i]); rgb.append(rgba[i + 1]); rgb.append(rgba[i + 2]) }
        return rgb
    }
}
