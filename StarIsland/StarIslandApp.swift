import SwiftUI
import SwiftData

@main
struct StarIslandApp: App {
    /// Ensures the images directory exists and runs startup checks.
    init() {
        _ = ImageStorageService.imagesDir

        // Registers background task handler and checks for today's backup.
        AutoBackupManager.shared.setup()

        // Run integrity check in the background.
        Task {
            let container = try? ModelContainer(for: Record.self)
            if let context = container?.mainContext {
                await IntegrityService.runAll(context: context)
            }
        }

        // ════════════════════════════════════════════════════════════
        //  🩺 Runtime Diagnostics (Phase 10+)
        // ════════════════════════════════════════════════════════════
        print("")
        print("========================================")
        print("  🩺 StarIsland Runtime Diagnostics")
        print("========================================")

        // 1. Permission descriptions
        print("── Permission Descriptions ──")
        let permissionKeys = [
            "NSCameraUsageDescription",
            "NSLocationWhenInUseUsageDescription",
            "NSPhotoLibraryUsageDescription",
            "NSPhotoLibraryAddUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSSpeechRecognitionUsageDescription",
        ]
        for key in permissionKeys {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "❌ MISSING"
            print("  \(key): \(value)")
        }

        // 2. App Icons
        print("── App Icons (CFBundleIcons) ──")
        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") {
            print("  \(icons)")
            if let primary = (icons as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any] {
                if let iconFiles = primary["CFBundleIconFiles"] as? [String] {
                    print("  CFBundleIconFiles: \(iconFiles)")
                }
                if let iconName = primary["CFBundleIconName"] as? String {
                    print("  CFBundleIconName: \(iconName)")
                }
            }
        } else {
            print("  ❌ CFBundleIcons not found in Info.plist")
        }

        print("========================================")
        print("")
    }

    @AppStorage(SettingsStorage.Keys.themeMode)
    private var themeMode: String = ThemeMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(resolvedScheme)
        }
        .modelContainer(for: Record.self)
    }

    // MARK: - Theme

    private var resolvedScheme: ColorScheme? {
        ThemeMode(rawValue: themeMode)?.colorScheme
    }
}
