import SwiftUI

// MARK: - Theme Mode

/// System‑wide appearance preference, stored in ``SettingsStorage``.
enum ThemeMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - App Theme

/// Central design token collection.
///
/// All values use Apple system defaults — no custom colours or fonts.
/// This file exists to name semantic constants, not to introduce
/// visual theming.
enum AppTheme {
    // MARK: - Spacing

    struct Spacing {
        let xxxsmall: CGFloat = 1
        let xxsmall: CGFloat = 2
        let xsmall: CGFloat = 4
        let small: CGFloat = 6
        let medium: CGFloat = 8
        let large: CGFloat = 12
        let xlarge: CGFloat = 16
        let xxlarge: CGFloat = 20
        let xxxlarge: CGFloat = 24
        let huge: CGFloat = 32
        let massive: CGFloat = 48

        // Phase 2 — image
        let photoSpacing: CGFloat = 4

        // Phase 2.5 — layout
        let headerSpacing: CGFloat = 32
        let sectionSpacing: CGFloat = 32
    }

    static let spacing = Spacing()

    // MARK: - Corner Radius

    struct CornerRadius {
        let small: CGFloat = 4
        let medium: CGFloat = 8
        let standard: CGFloat = 10
        let large: CGFloat = 12

        // Phase 2 — image
        let image: CGFloat = 16

        // Phase 2.5 — search
        let searchBar: CGFloat = 10

        // Phase 3 — stats
        let statsCard: CGFloat = 12
    }

    static let cornerRadius = CornerRadius()

    // MARK: - Timeline Metrics

    struct Timeline {
        /// Width of the left timeline indicator column (dot + line).
        let indicatorWidth: CGFloat = 24
        /// Diameter of the dot on the timeline.
        let dotSize: CGFloat = 7
        /// Width of the timeline vertical line.
        let lineWidth: CGFloat = 1
    }

    static let timeline = Timeline()

    // MARK: - Search

    struct Search {
        /// Fixed height for the search bar container.
        let barHeight: CGFloat = 44
    }

    static let search = Search()

    // MARK: - Heatmap / Archive

    struct Heatmap {
        /// Width & height of each day cell in the contribution grid.
        let cellSize: CGFloat = 12
        /// Spacing between cells.
        let cellSpacing: CGFloat = 3
        /// Spacing between week columns.
        let weekSpacing: CGFloat = 4
    }

    static let heatmap = Heatmap()

    // MARK: - Animation (Phase 4.5 — unified)

    struct AnimationDuration {
        /// Quick insert / delete (0.30 s)
        let insertDuration: Double = 0.30
        /// Hero image transition (0.35 s)
        let heroDuration: Double = 0.35
        /// Soft‑delete / permanent delete (0.25 s)
        let deleteDuration: Double = 0.25
        /// Section header appearance (0.20 s)
        let sectionDuration: Double = 0.20
        /// Spring animation used everywhere
        var spring: Animation {
            .interactiveSpring(response: 0.35, dampingFraction: 0.86)
        }
        /// Softer spring for hero transitions
        var heroSpring: Animation {
            .interactiveSpring(response: heroDuration, dampingFraction: 0.85)
        }

        // Legacy — kept for backward compatibility
        let `default`: Double = 0.2
        let slow: Double = 0.35

        // Phase 2.5
        let insert: Double = 0.30
        let hero: Double = 0.35
        let delete: Double = 0.25
    }

    static let animationDuration = AnimationDuration()
}
