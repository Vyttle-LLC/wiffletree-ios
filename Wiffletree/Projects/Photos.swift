import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A photo ready to attach: a JPEG no larger than `Photo.longestSide` on its long side, upright,
/// without the original's metadata, and a small image for the composer.
struct Photo: Sendable {
    /// Large enough to read a screenshot or a whiteboard; small enough to upload quickly over
    /// Tailscale.
    static let longestSide = 2048
    /// The thumbnails' long side, sharp at three times their size on screen.
    static let thumbnailSide = 360

    let jpeg: Data
    let thumbnail: UIImage

    /// Converts any image ImageIO reads, HEIC included, or nil when `data` is not one.
    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = Self.image(from: source, longestSide: Self.longestSide),
              let jpeg = Self.jpeg(full),
              let thumbnail = Self.image(from: source, longestSide: Self.thumbnailSide)
        else { return nil }
        self.jpeg = jpeg
        self.thumbnail = UIImage(cgImage: thumbnail)
    }

    /// A camera shot.
    init?(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 1) else { return nil }
        self.init(data: data)
    }

    /// A small upright image of an image file's bytes, such as a sent attachment.
    static func thumbnail(of data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = image(from: source, longestSide: thumbnailSide)
        else { return nil }
        return UIImage(cgImage: image)
    }

    /// The image turned upright and scaled down to fit `longestSide`, never up.
    private static func image(from source: CGImageSource, longestSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// The system camera, for taking one photo.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
