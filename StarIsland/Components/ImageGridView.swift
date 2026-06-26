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
///
/// ## T4.7 — Timeline layout modes
/// - `fitSingleImage`: single image uses `.scaledToFit()` + `maxHeight: 300`
/// - `useStrictGrid`: multi-image uses 110×110 square grid (2/2×2/3×3)
struct ImageGridView: View {
    let imagePaths: [String]

    var maxDisplay: Int = 9
    /// When set, overrides the dynamic grid height.
    /// Used by RecordDetailView for standard layout.
    var fixedHeight: CGFloat?

    // T4.7 — Timeline layout modes
    var fitSingleImage: Bool = false
    var useStrictGrid: Bool = false

    // Hero transition support (optional)
    var heroNamespace: Namespace.ID?
    var heroFilename: String?
    var onTapImage: (([String], Int) -> Void)?

    @State private var viewerIndex: Int?
    @State private var showViewer = false
    @State private var scaleValues: [String: CGFloat] = [:]
    @State private var opacities: [String: CGFloat] = [:]

    // MARK: - Body

    /// Fixed height: 220 pt for single image, 240 pt for multiple,
    /// unless `fixedHeight` is provided.
    private var gridHeight: CGFloat {
        if let fixedHeight { return fixedHeight }
        let displayPaths = Array(imagePaths.prefix(maxDisplay))
        return displayPaths.count == 1 ? 220 : 240
    }

    var body: some View {
        layoutContent
            .fullScreenCover(isPresented: $showViewer) {
                PhotoViewer(imagePaths: imagePaths,
                            initialIndex: viewerIndex ?? 0)
            }
    }

    // MARK: - Layout Content

    @ViewBuilder
    private var layoutContent: some View {
        let displayPaths = Array(imagePaths.prefix(maxDisplay))
        let overflow = imagePaths.count - maxDisplay

        if fitSingleImage && displayPaths.count == 1 {
            // T4.7 — Timeline single: scaledToFit, full width, maxHeight 300
            singleFitLayout(displayPaths[0])
        } else if useStrictGrid && displayPaths.count >= 2 {
            // T4.7 — Timeline multi: 110×110 strict grid
            strictGridLayout(displayPaths, overflow: overflow)
                .frame(height: strictGridHeight(displayPaths.count))
                .clipped()
        } else {
            // Standard layout
            Group {
                switch displayPaths.count {
                case 1:  singleLayout(displayPaths)
                case 2:  doubleLayout(displayPaths)
                case 3:  tripleLayout(displayPaths)
                case 4:  gridLayout(displayPaths, columns: 2)
                default: gridLayout(displayPaths, columns: 3, overflow: overflow)
                }
            }
            .frame(height: gridHeight)
            .clipped()
        }
    }

    // MARK: - T4.7 Timeline Single Image (scaledToFit)

    private func singleFitLayout(_ filename: String) -> some View {
        let heroID = "hero-image-\(filename)"
        let isHero = heroNamespace != nil

        return LocalImage(filename: filename)
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.image,
                                        style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.image))
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
            .matchedGeometryEffectIfAvailable(id: heroID, in: heroNamespace, isSource: heroFilename != filename)
            .opacity(isHero && heroFilename == filename ? 0 : 1)
            .scaleEffect(scaleValues[filename] ?? 1)
            .opacity(opacities[filename] ?? 1)
            .onTapGesture {
                if let onTapImage {
                    onTapImage(imagePaths, 0)
                } else {
                    viewerIndex = 0
                    showViewer = true
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scaleValues[filename] = 1
                    opacities[filename] = 1
                }
            }
    }

    // MARK: - T4.7 Timeline Strict Grid (110×110 cells)

    private func strictGridHeight(_ count: Int) -> CGFloat {
        let columns = count <= 4 ? 2 : 3
        let rows = (count + columns - 1) / columns
        return CGFloat(rows) * 110 + CGFloat(rows - 1) * AppTheme.spacing.photoSpacing
    }

    private func strictGridLayout(_ paths: [String], overflow: Int) -> some View {
        let columns = paths.count <= 4 ? 2 : 3
        let rows = (paths.count + columns - 1) / columns

        return VStack(spacing: AppTheme.spacing.photoSpacing) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: AppTheme.spacing.photoSpacing) {
                    ForEach(0 ..< columns, id: \.self) { col in
                        let idx = row * columns + col
                        if idx < paths.count {
                            ZStack(alignment: .bottomTrailing) {
                                strictThumb(paths[idx], index: idx)

                                if idx == paths.count - 1 && overflow > 0 {
                                    overflowBadge(overflow)
                                }
                            }
                            .frame(width: 110, height: 110)
                        }
                    }
                }
            }
        }
    }

    private func strictThumb(_ filename: String, index: Int) -> some View {
        let heroID = "hero-image-\(filename)"
        let isHero = heroNamespace != nil

        return LocalImage(filename: filename)
            .scaledToFill()
            .frame(width: 110, height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
            .matchedGeometryEffectIfAvailable(id: heroID, in: heroNamespace, isSource: heroFilename != filename)
            .opacity(isHero && heroFilename == filename ? 0 : 1)
            .scaleEffect(scaleValues[filename] ?? 1)
            .opacity(opacities[filename] ?? 1)
            .onTapGesture {
                if let onTapImage {
                    onTapImage(imagePaths, index)
                } else {
                    viewerIndex = index
                    showViewer = true
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scaleValues[filename] = 1
                    opacities[filename] = 1
                }
            }
    }

    // MARK: - Standard Layouts

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
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
            .matchedGeometryEffectIfAvailable(
                id: heroID,
                in: heroNamespace,
                isSource: heroFilename != filename
            )
            .opacity(isHero && heroFilename == filename ? 0 : 1)
            .scaleEffect(scaleValues[filename] ?? 1)
            .opacity(opacities[filename] ?? 1)
            .onTapGesture {
                if let onTapImage {
                    onTapImage(imagePaths, index)
                } else {
                    viewerIndex = index
                    showViewer = true
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scaleValues[filename] = 1
                    opacities[filename] = 1
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