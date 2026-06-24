import Foundation
import SwiftUI

// MARK: - Settings Storage

/// Centralised `@AppStorage` wrapper — single source of truth for all
/// user preferences.  No other file should read or write `UserDefaults`
/// keys directly.
///
/// ```
/// @AppStorage(SettingsStorage.Keys.autoBackupEnabled)
/// var autoBackupEnabled = false
/// ```
///
/// When adding a new preference, declare its key in ``Keys`` and add
/// a computed property here with the default value expressed in the
/// property declaration.
struct SettingsStorage {

    // MARK: - Keys

    enum Keys {
        static let autoBackupEnabled = "auto_backup_enabled"
        static let backupLimit       = "backup_limit"
        static let selectedIcon      = "selected_icon"
        static let themeMode         = "theme_mode"
    }

    // MARK: - Properties

    /// Whether the app should generate daily automatic backups.
    @AppStorage(Keys.autoBackupEnabled)
    static var autoBackupEnabled = false

    /// Maximum number of automatic backups to retain on disk.
    @AppStorage(Keys.backupLimit)
    static var backupLimit = 30

    /// Selected alternate app icon name, or `"default"` for the original icon.
    @AppStorage(Keys.selectedIcon)
    static var selectedIcon = "default"

    /// Color scheme preference: `"system"`, `"light"`, or `"dark"`.
    @AppStorage(Keys.themeMode)
    static var themeMode: String = ThemeMode.system.rawValue

    /// Convenience accessor returning a ``ThemeMode`` value.
    static var resolvedThemeMode: ThemeMode {
        get { ThemeMode(rawValue: themeMode) ?? .system }
        set { themeMode = newValue.rawValue }
    }
}
