import Foundation
import AppKit

struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let imageData: Data
    let mediaType: String
    let thumbnail: NSImage

    static func == (lhs: ImageAttachment, rhs: ImageAttachment) -> Bool {
        lhs.id == rhs.id
    }

    /// Maximum allowed file size: 5 MB.
    static let maxFileSize: Int = 5 * 1024 * 1024

    /// Maximum number of attachments per instruction.
    static let maxAttachments: Int = 5

    /// Thumbnail size for the preview strip.
    static let thumbnailSize: CGFloat = 48

    /// Supported image file extensions.
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]

    // MARK: - Factory

    /// Create an attachment from a file URL. Returns nil if the file cannot
    /// be read, exceeds the size limit, or is not a supported image format.
    static func fromURL(_ url: URL) -> ImageAttachment? {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }
        guard data.count <= maxFileSize else { return nil }

        guard let nsImage = NSImage(data: data) else { return nil }

        let thumb = generateThumbnail(from: nsImage, size: thumbnailSize)

        return ImageAttachment(
            id: UUID(),
            fileName: url.lastPathComponent,
            imageData: data,
            mediaType: mediaTypeForExtension(ext),
            thumbnail: thumb
        )
    }

    /// Base64-encoded string of the image data (used for API payloads).
    var base64Encoded: String {
        imageData.base64EncodedString()
    }

    // MARK: - Helpers

    static func mediaTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "image/png"
        }
    }

    private static func generateThumbnail(from image: NSImage, size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        return NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
            return true
        }
    }
}
