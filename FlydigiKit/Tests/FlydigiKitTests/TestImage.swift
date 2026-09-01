import Foundation
import ImageIO
import CoreGraphics

/// Decodes a PNG to tightly packed RGB8 using ImageIO (test helper; the app uses the same stack).
enum TestImage {
    static func rgb8(png: [UInt8]) -> [UInt8]? {
        guard let src = CGImageSourceCreateWithData(Data(png) as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rgb = [UInt8](); rgb.reserveCapacity(w * h * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) { rgb += [rgba[i], rgba[i + 1], rgba[i + 2]] }
        return rgb
    }
}
