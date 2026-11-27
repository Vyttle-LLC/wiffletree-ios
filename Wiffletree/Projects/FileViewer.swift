import QuickLook
import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// A file on the host that the chat is opening.
struct OpenedFile: Identifiable {
    let path: String

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

/// A file from the host in Quick Look, with Share, which saves it to Files or Photos. It loads
/// with progress, says why when it cannot, and stops waiting for it when dismissed.
struct FileViewer: View {
    @Environment(LiveHost.self) private var host
    @Environment(\.dismiss) private var dismiss
    let chat: ProjectChat
    let file: OpenedFile
    @State private var copy: Result<URL, any Error>?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tidal.base)
                .navigationTitle(file.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    if case .success(let url) = copy {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: url)
                        }
                    }
                }
        }
        .task {
            do {
                copy = .success(try await chat.copy(of: file.path))
            } catch is CancellationError {
            } catch {
                copy = .failure(error)
            }
        }
        .onDisappear {
            if case .success(let url) = copy { chat.removeCopy(url) }
        }
    }

    @ViewBuilder private var content: some View {
        switch copy {
        case nil:
            ProgressView("Loading from \(host.name)…")
        case .success(let url):
            QuickLookPreview(url: url).ignoresSafeArea(edges: .bottom)
        case .failure(let error):
            ContentUnavailableView(
                "Couldn't open \(file.name)",
                systemImage: "exclamationmark.circle",
                description: Text(host.failureText(error))
            )
        }
    }
}

/// Quick Look's preview of one local file.
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return preview
    }

    func updateUIViewController(_ preview: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        preview.reloadData()
    }

    func makeCoordinator() -> Source { Source(url: url) }

    final class Source: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

/// Thumbnails of the images a message links to, at most `shown`, each opening the file. They
/// load only while the message is on screen.
struct LinkedImages: View {
    @Environment(\.openURL) private var openURL
    let chat: ProjectChat
    let paths: [String]

    private let shown = 4

    var body: some View {
        HStack(spacing: 6) {
            ForEach(paths.prefix(shown), id: \.self) { path in
                let name = (path as NSString).lastPathComponent
                Button { openURL(FileLinks.url(for: path)) } label: {
                    Thumbnail(image: chat.thumbnails[path], isUnreadable: chat.unreadable.contains(path), name: name, side: 72)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(name)")
                .task { await chat.loadThumbnail(of: path) }
            }
            if paths.count > shown {
                Text("+\(paths.count - shown) more")
                    .font(.footnote)
                    .foregroundStyle(Tidal.subtle)
            }
        }
    }
}

/// A square image from the host, a spinner while it loads, or a photo symbol when it could not be
/// read.
struct Thumbnail: View {
    let image: UIImage?
    var isUnreadable = false
    let name: String
    let side: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if isUnreadable {
                Tidal.overlay.overlay(Image(systemName: "photo").foregroundStyle(Tidal.subtle))
            } else {
                Tidal.overlay.overlay(ProgressView())
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isImage)
    }
}
