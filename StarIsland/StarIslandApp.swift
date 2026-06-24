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
