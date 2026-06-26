import SwiftUI

// MARK: - Image Grid View

/// Dynamic image grid following the Phase 2 layout rules.
///
/// When `heroNamespace` and `heroFilename` are provided the grid participates
/// in a **hero transition** (matched‑geometry effect) orchestrated by the
/// parent's `ZStack` overlay.  The parent controls the transition lifecycle.
///
/// **Standard mode** (no namespace): the grid presents ``PhotoViewer`` via
/// its own `fullScreenCover` on tap.
struct ImageGridView: View {
    let imagePaths: [String]

    var maxDisplay: Int = 9

    // Hero transition support (optional)
    var heroNamespace: Namespace.ID?
    var heroFilename: String?
    var onTapImage: (([String], Int) -> Void)?

    @State private var viewerIndex: Int?
    @State private var showViewer = false

    // MARK: - Body

    var body: some View {
        let displayPaths = Array(imagePaths.prefix(maxDisplay))
        let overflow = imagePaths.count - maxDisplay

        // 🩺 Diagnostics: log image count and selected layout
        let _ = {
            let tag: String
            switch displayPaths.count {
            case 1:  tag = "single(4:3)"
            case 2:  tag = "double(1:1×2)"
            case 3:  tag = "triple(16:9 + 1:1×2)"
            case 4:  tag = "grid(2×2)"
            default: tag = "grid(3×N)"
            }
            print("[ImageGrid] total=\(imagePaths.count) display=\(displayPaths.count) layout=\(tag) overflow=\(overflow)")
        }()

        Group {
            switch displayPaths.count {
            case 1:  singleLayout(displayPaths)
            case 2:  doubleLayout(displayPaths)
            case 3:  tripleLayout(displayPaths)
            case 4:  gridLayout(displayPaths, columns: 2)
            default: gridLayout(displayPaths, columns: 3, overflow: overflow)
            }
        }
        .fullScreenCover(isPresented: $showViewer) {
            PhotoViewer(imagePaths: imagePaths,
                        initialIndex: viewerIndex ?? 0)
        }
    }

    // MARK: - Layouts

    private func singleLayout(_ paths: [String]) -> some View {
        thumb(paths[0], aspectRatio: 4 / 3, index: 0)
    }

    private func doubleLayout(_ paths: [String]) -> some View {
        HStack(spacing: AppTheme.spacing.photoSpacing) {
            ForEach(paths.indices, id: \.self) { i in
                thumb(paths[i], aspectRatio: 1, index: i)
            }
        }
    }

    private func tripleLayout(_ paths: [String]) -> some View {
        VStack(spacing: AppTheme.spacing.photoSpacing) {
            thumb(paths[0], aspectRatio: 16 / 9, index: 0)

            HStack(spacing: AppTheme.spacing.photoSpacing) {
                thumb(paths[1], aspectRatio: 1, index: 1)
                thumb(paths[2], aspectRatio: 1, index: 2)
            }
        }
    }

    private func gridLayout(_ paths: [String],
                            columns: Int,
                            overflow: Int = 0) -> some View {
        let rows = (paths.count + columns - 1) / columns

        return VStack(spacing: AppTheme.spacing.photoSpacing) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: AppTheme.spacing.photoSpacing) {
                    ForEach(0 ..< columns, id: \.self) { col in
                        let idx = row * columns + col
                        if idx < paths.count {
                            ZStack(alignment: .bottomTrailing) {
                                thumb(paths[idx], aspectRatio: 1, index: idx)

                                if idx == paths.count - 1 && overflow > 0 {
                                    overflowBadge(overflow)
                                }
                            }
                        } else {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Thumbnail

    private func thumb(_ filename: String,
                       aspectRatio: CGFloat,
                       index: Int) -> some View {
        let heroID = "hero-image-\(filename)"
        let isHero = heroNamespace != nil

        return LocalImage(filename: filename)
            .aspectRatio(aspectRatio, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.image,
                                        style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.image))
            .clipped()
            .matchedGeometryEffectIfAvailable(
                id: heroID,
                in: heroNamespace,
                isSource: heroFilename != filename
            )
            .opacity(isHero && heroFilename == filename ? 0 : 1)
            .onTapGesture {
                if let onTapImage {
                    onTapImage(imagePaths, index)
                } else {
                    viewerIndex = index
                    showViewer = true
                }
            }
    }

    private func overflowBadge(_ count: Int) -> some View {
        Text("+\(count)")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(6)
    }
}

// MARK: - Local Image Loader (with cache)

private struct LocalImage: View {
    let filename: String

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                            .controlSize(.mini)
                    }
            }
        }
        .task(priority: .medium) { await load() }
    }

    private func load() async {
        guard uiImage == nil else { return }
        let image = await ImageCacheService.shared.load(filename: filename)
        if let image {
            print("[ImageGrid] LocalImage loaded: \(filename) \(Int(image.size.width))×\(Int(image.size.height)) scale=\(image.scale)")
        } else {
            print("[ImageGrid] LocalImage nil: \(filename)")
        }
        await MainActor.run { uiImage = image }
    }
}

// MARK: - Matched Geometry Helper

extension View {
    @ViewBuilder
    fileprivate func matchedGeometryEffectIfAvailable(
        id: String,
        in namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id,
                                       in: namespace,
                                       isSource: isSource)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("1 image") {
    ImageGridView(imagePaths: [])
        .frame(width: 200)
        .padding()
}
