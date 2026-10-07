import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

enum PlatformImageFactory {
    static func named(_ name: String) -> PlatformImage? {
        #if canImport(UIKit)
        UIImage(named: name)
        #else
        NSImage(named: name)
        #endif
    }

    static func from(data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        UIImage(data: data)
        #else
        NSImage(data: data)
        #endif
    }

    static func pngData(from image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        image.pngData()
        #else
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }

    static func resizedForExportLogo(_ image: PlatformImage, maxDimension: CGFloat) -> PlatformImage {
        #if canImport(UIKit)
        let size = image.size
        #else
        let size = image.size
        #endif
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        #else
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        return resized
        #endif
    }
}
