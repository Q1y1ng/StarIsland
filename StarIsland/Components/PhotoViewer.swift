import SwiftUI

// MARK: - Photo Viewer

/// Full-screen image browser with swipe-to-navigate.
///
/// Supports:
/// - Left / right swipe via ``TabView`` with page style
/// - Pinch-to-zoom on each image
/// - Close button in the top trailing corner
///
/// When `namespace` and `heroID` are provided the viewer participates in
/// a **hero transition** (matched‑geometry effect) orchestrated by the
/// parent view's `ZStack` overlay.
struct PhotoViewer: View {
    let imagePaths: [String]
    let initialIndex: Int

    // Hero transition support (optional)
    var namespace: Namespace.ID?
    var heroID: String?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int

    init(imagePaths: [String],
         initialIndex: Int = 0,
         namespace: Namespace.ID? = nil,
         heroID: String? = nil,
         onDismiss: (() -> Void)? = nil) {
        self.imagePaths = imagePaths
        self.initialIndex = initialIndex
        self.namespace = namespace
        self.heroID = heroID
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ── Background ──────────────────────────────────────────
            Color.black
                .ignoresSafeArea()

            // ── Page view ───────────────────────────────────────────
            TabView(selection: $currentIndex) {
                ForEach(imagePaths.indices, id: \.self) { idx in
                    ZoomableImage(filename: imagePaths[idx],
                                  namespace: namespace,
                                  heroID: heroID)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // ── Close button ────────────────────────────────────────
            Button {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                    .background(Circle().fill(.black.opacity(0.4)))
                    .padding(AppTheme.spacing.medium)
            }
            .padding(AppTheme.spacing.xlarge)
        }
        .statusBar(hidden: true)
    }
}

// MARK: - Zoomable Image

private struct ZoomableImage: View {
    let filename: String
    let namespace: Namespace.ID?
    let heroID: String?

    @State private var uiImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .matchedGeometry(id: "hero-image-\(filename)",
                                         in: namespace,
                                         isSource: false)
                        .gesture(magnificationGesture)
                        .gesture(dragGesture)
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(priority: .high) { await load() }
    }

    // MARK: - Load

    private func load() async {
        let image = await ImageCacheService.shared.load(filename: filename)
        await MainActor.run { uiImage = image }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale = $0 }
            .onEnded { finalScale in
                withAnimation(.spring(response: 0.25)) {
                    scale = max(1.0, min(finalScale, 4.0))
                    if scale == 1.0 { offset = .zero }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { delta in
                guard scale > 1.0 else { return }
                offset = delta.translation
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.25)) {
                    if scale == 1.0 { offset = .zero }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.25)) {
            if scale > 1.0 {
                scale = 1.0
                offset = .zero
            } else {
                scale = 2.5
            }
        }
    }
}

// MARK: - Matched Geometry Helper

extension View {
    @ViewBuilder
    fileprivate func matchedGeometry(id: String,
                                     in namespace: Namespace.ID?,
                                     isSource: Bool) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoViewer(imagePaths: [], initialIndex: 0)
}
