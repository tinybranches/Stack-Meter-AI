import Foundation

enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case ukrainian

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .system: return L10n.tr("language.system")
        case .english: return "English"
        case .ukrainian: return "Українська"
        }
    }
}

enum ResolvedLanguage: String, Sendable {
    case english = "en"
    case ukrainian = "uk"

    var locale: Locale {
        Locale(identifier: rawValue == "uk" ? "uk_UA" : "en_US")
    }

    static func fromSystem() -> ResolvedLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("uk") { return .ukrainian }
        if preferred.hasPrefix("en") { return .english }
        return .english
    }

    static func resolve(preference: LanguagePreference) -> ResolvedLanguage {
        switch preference {
        case .system: return fromSystem()
        case .english: return .english
        case .ukrainian: return .ukrainian
        }
    }
}

/// Thread-safe current language for use from providers and UI.
enum LanguageRuntime {
    private static let lock = NSLock()
    private static var _current: ResolvedLanguage = {
        let raw = UserDefaults.standard.string(forKey: "languagePreference")
        let preference = raw.flatMap(LanguagePreference.init(rawValue:)) ?? .system
        return ResolvedLanguage.resolve(preference: preference)
    }()

    static var current: ResolvedLanguage {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    static func setCurrent(_ language: ResolvedLanguage) {
        lock.lock()
        _current = language
        lock.unlock()
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published private(set) var resolved: ResolvedLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: "languagePreference")
        let preference = raw.flatMap(LanguagePreference.init(rawValue:)) ?? .system
        let language = ResolvedLanguage.resolve(preference: preference)
        resolved = language
        LanguageRuntime.setCurrent(language)
    }

    func apply(preference: LanguagePreference) {
        let language = ResolvedLanguage.resolve(preference: preference)
        resolved = language
        LanguageRuntime.setCurrent(language)
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        let lang = LanguageRuntime.current
        return table[key]?[lang] ?? table[key]?[.english] ?? key
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: LanguageRuntime.current.locale, arguments: args)
    }

    static func hasKey(_ key: String) -> Bool {
        table[key] != nil
    }

    /// If `value` is a known l10n key, translate it; otherwise return as-is.
    static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        if hasKey(value) { return tr(value) }
        return value
    }

    private static let table: [String: [ResolvedLanguage: String]] = [
        "language.system": [
            .english: "System",
            .ukrainian: "Системна",
        ],
        "language.section": [
            .english: "Language",
            .ukrainian: "Мова",
        ],
        "language.picker": [
            .english: "App language",
            .ukrainian: "Мова застосунку",
        ],
        "language.hint": [
            .english: "System follows Ukrainian or English from macOS. Any other system language defaults to English.",
            .ukrainian: "Системна бере українську або англійську з macOS. Інші мови системи — англійська за замовчуванням.",
        ],

        "common.cancel": [.english: "Cancel", .ukrainian: "Скасувати"],
        "common.refresh": [.english: "Refresh", .ukrainian: "Оновити"],
        "common.refreshing": [.english: "Refreshing…", .ukrainian: "Оновлення…"],
        "common.settings": [.english: "Settings", .ukrainian: "Налаштування"],
        "common.quit": [.english: "Quit", .ukrainian: "Вийти"],
        "common.status": [.english: "Status", .ukrainian: "Статус"],

        "status.active": [.english: "Active", .ukrainian: "Активний"],
        "status.rateLimited": [.english: "Rate limited", .ukrainian: "Ліміт вичерпано"],
        "status.authNeeded": [.english: "Auth needed", .ukrainian: "Потрібна авторизація"],
        "status.unavailable": [.english: "Unavailable", .ukrainian: "Недоступно"],
        "status.loading": [.english: "Loading", .ukrainian: "Завантаження"],

        "popover.noProvider": [.english: "No provider selected", .ukrainian: "Провайдер не вибраний"],
        "popover.fetching": [.english: "Fetching usage…", .ukrainian: "Завантаження використання…"],
        "popover.noWindows": [
            .english: "No rate-limit windows reported.",
            .ukrainian: "Вікна лімітів не повідомлені.",
        ],
        "popover.spend": [.english: "Spend", .ukrainian: "Витрати"],
        "popover.credits": [.english: "Credits $%.2f", .ukrainian: "Кредити $%.2f"],
        "popover.usedUSD": [.english: "Used $%.2f", .ukrainian: "Використано $%.2f"],
        "popover.tokens": [.english: "Tokens", .ukrainian: "Токени"],
        "popover.tokensToday": [.english: "Today %@", .ukrainian: "Сьогодні %@"],
        "popover.tokensMonth": [.english: "Month %@", .ukrainian: "Місяць %@"],
        "popover.updated": [.english: "Updated %@", .ukrainian: "Оновлено %@"],
        "popover.usedPercent": [.english: "%d%% used", .ukrainian: "%d%% використано"],
        "popover.leftPercent": [.english: "%d%% left", .ukrainian: "%d%% залишилось"],
        "popover.resets": [.english: "Resets %@", .ukrainian: "Скидання %@"],

        "auth.title": [.english: "Authorize ChatGPT", .ukrainian: "Авторизувати ChatGPT"],
        "auth.needed": [
            .english: "ChatGPT is not authorized in Stack Meter AI yet.",
            .ukrainian: "ChatGPT ще не авторизований у Stack Meter AI.",
        ],
        "auth.expired": [
            .english: "ChatGPT session expired. Sign in again to continue.",
            .ukrainian: "Сесію ChatGPT завершено. Увійдіть знову, щоб продовжити.",
        ],
        "auth.rateLimitedTemp": [
            .english: "Temporarily rate limited while fetching usage.",
            .ukrainian: "Тимчасово обмежено під час отримання використання.",
        ],
        "auth.chatgpt.title": [.english: "Authorize ChatGPT", .ukrainian: "Авторизувати ChatGPT"],
        "auth.chatgpt.needed": [
            .english: "Sign in with ChatGPT to track Codex and ChatGPT usage.",
            .ukrainian: "Увійдіть через ChatGPT, щоб бачити ліміти Codex і ChatGPT.",
        ],
        "auth.chatgpt.expired": [
            .english: "ChatGPT session expired. Sign in again.",
            .ukrainian: "Сесію ChatGPT завершено. Увійдіть знову.",
        ],
        "auth.chatgpt.browserLogin": [
            .english: "Sign in with ChatGPT",
            .ukrainian: "Увійти через ChatGPT",
        ],
        "auth.chatgpt.fromCLI": [
            .english: "Authorize with Codex CLI login",
            .ukrainian: "Авторизувати з входу Codex CLI",
        ],
        "auth.chatgpt.hint": [
            .english: "One ChatGPT login unlocks both Codex and ChatGPT. If in-app Google login fails, run `codex login` then use “Authorize with Codex CLI login”.",
            .ukrainian: "Один вхід ChatGPT відкриває і Codex, і ChatGPT. Якщо Google у вікні не входить — виконайте `codex login`, потім «Авторизувати з входу Codex CLI».",
        ],
        "auth.chatgpt.loginTitle": [
            .english: "ChatGPT login",
            .ukrainian: "Вхід ChatGPT",
        ],
        "auth.chatgpt.loginHint": [
            .english: "Sign in to ChatGPT in the window below.",
            .ukrainian: "Увійдіть у ChatGPT у вікні нижче.",
        ],
        "auth.chatgpt.passkeyHint": [
            .english: "If Google asks for Bluetooth or a phone nearby, tap “Another way” and sign in with your password (or use Codex CLI import instead). Passkeys often fail in this window.",
            .ukrainian: "Якщо Google просить Bluetooth або телефон поруч — натисніть «Інший спосіб» і ввійдіть паролем (або імпортуйте сесію Codex CLI). Passkey у цьому вікні часто не працює.",
        ],
        "auth.chatgpt.googleHint": [
            .english: "Google sign-in: prefer password via “Another way” if Passkey/Bluetooth fails.",
            .ukrainian: "Вхід Google: якщо Passkey/Bluetooth не спрацював — «Інший спосіб» → пароль.",
        ],
        "auth.chatgpt.checkingSession": [
            .english: "Waiting for login…",
            .ukrainian: "Очікування входу…",
        ],
        "auth.chatgpt.success": [
            .english: "ChatGPT authorized.",
            .ukrainian: "ChatGPT авторизовано.",
        ],
        "auth.chatgpt.emptyToken": [
            .english: "Access token is empty.",
            .ukrainian: "Токен доступу порожній.",
        ],
        "auth.connecting": [
            .english: "Connecting…",
            .ukrainian: "Підключення…",
        ],
        "auth.signOut": [
            .english: "Sign out",
            .ukrainian: "Вийти",
        ],
        "auth.authorized": [.english: "Authorized", .ukrainian: "Авторизовано"],
        "auth.notAuthorized": [.english: "Not authorized", .ukrainian: "Не авторизовано"],
        "auth.cliMissing": [
            .english: "No Codex CLI login found. Run `codex login` first, then authorize Stack Meter AI.",
            .ukrainian: "Немає входу Codex CLI. Спочатку виконайте `codex login`, потім авторизуйте Stack Meter AI.",
        ],
        "auth.cliBadToken": [
            .english: "Codex auth.json is missing an access token. Run `codex login` again.",
            .ukrainian: "У auth.json немає access token. Знову виконайте `codex login`.",
        ],

        "settings.refresh": [.english: "Refresh", .ukrainian: "Оновлення"],
        "settings.interval": [.english: "Interval", .ukrainian: "Інтервал"],
        "settings.menuBar": [.english: "Menu bar", .ukrainian: "Рядок меню"],
        "settings.showPercent": [
            .english: "Show usage % in tray",
            .ukrainian: "Показувати % використання в треї",
        ],
        "settings.notifications": [.english: "Notifications", .ukrainian: "Сповіщення"],
        "settings.warning": [.english: "Warning", .ukrainian: "Попередження"],
        "settings.critical": [.english: "Critical", .ukrainian: "Критичний"],
        "notify.toggle.usageThreshold": [
            .english: "Usage threshold alerts",
            .ukrainian: "Сповіщення про поріг usage",
        ],
        "notify.toggle.rateLimited": [
            .english: "Rate limit reached",
            .ukrainian: "Ліміт вичерпано",
        ],
        "notify.toggle.limitReset": [
            .english: "Limit reset available",
            .ukrainian: "Ліміт знову доступний",
        ],
        "notify.toggle.usageJump": [
            .english: "Sudden usage jump",
            .ukrainian: "Різкий стрибок usage",
        ],
        "notify.toggle.sessionExpired": [
            .english: "Codex session expired",
            .ukrainian: "Сесію Codex завершено",
        ],
        "notify.toggle.lowCredits": [
            .english: "Low credits balance",
            .ukrainian: "Мало кредитів",
        ],
        "notify.jumpThreshold": [
            .english: "Jump size",
            .ukrainian: "Розмір стрибка",
        ],
        "notify.creditsThreshold": [
            .english: "Credits floor",
            .ukrainian: "Мінімум кредитів",
        ],
        "notify.togglesHint": [
            .english: "On first launch you will be asked for permission. Alerts only fire for toggles you enable.",
            .ukrainian: "При першому запуску буде запит дозволу. Сповіщення лише для увімкнених пунктів.",
        ],
        "notify.prompt.title": [
            .english: "Allow notifications?",
            .ukrainian: "Дозволити сповіщення?",
        ],
        "notify.prompt.body": [
            .english: "Stack Meter AI can alert you when usage is high, limits reset, or a session expires. You can change this later in Settings.",
            .ukrainian: "Stack Meter AI може попереджати про високе використання, скидання лімітів або завершення сесії. Пізніше це можна змінити в Налаштуваннях.",
        ],
        "notify.prompt.allow": [
            .english: "Allow",
            .ukrainian: "Дозволити",
        ],
        "notify.prompt.notNow": [
            .english: "Not Now",
            .ukrainian: "Не зараз",
        ],
        "notify.permission.status": [
            .english: "Permission",
            .ukrainian: "Дозвіл",
        ],
        "notify.permission.allowed": [
            .english: "Allowed",
            .ukrainian: "Дозволено",
        ],
        "notify.permission.off": [
            .english: "Not allowed",
            .ukrainian: "Не дозволено",
        ],
        "notify.permission.denied": [
            .english: "Denied in System Settings",
            .ukrainian: "Заборонено в Системних налаштуваннях",
        ],
        "notify.permission.enable": [
            .english: "Allow notifications…",
            .ukrainian: "Дозволити сповіщення…",
        ],
        "notify.permission.enableHint": [
            .english: "If you chose Not Now on first launch, tap here to allow alerts.",
            .ukrainian: "Якщо при першому запуску натиснули «Не зараз», натисніть тут, щоб дозволити сповіщення.",
        ],
        "notify.permission.openSystemHint": [
            .english: "macOS blocked alerts. This opens System Settings so you can enable them for Stack Meter AI.",
            .ukrainian: "macOS заблокував сповіщення. Відкриються Системні налаштування — увімкніть їх для Stack Meter AI.",
        ],
        "notify.title": [.english: "%@ usage", .ukrainian: "Використання %@"],
        "notify.critical": [
            .english: "Critical: %d%% used",
            .ukrainian: "Критично: %d%% використано",
        ],
        "notify.warning": [
            .english: "Warning: %d%% used",
            .ukrainian: "Увага: %d%% використано",
        ],
        "notify.rateLimited": [
            .english: "Rate limit reached. Wait for reset or check Usage.",
            .ukrainian: "Ліміт вичерпано. Зачекайте скидання або перевірте Usage.",
        ],
        "notify.limitReset": [
            .english: "Limit reset: %@ is available again.",
            .ukrainian: "Ліміт скинуто: %@ знову доступний.",
        ],
        "notify.usageJump": [
            .english: "Usage jumped +%d%% (now %d%%).",
            .ukrainian: "Usage зріс на +%d%% (зараз %d%%).",
        ],
        "notify.sessionExpired": [
            .english: "Session expired. Authorize Codex again.",
            .ukrainian: "Сесію завершено. Авторизуйте Codex знову.",
        ],
        "notify.lowCredits": [
            .english: "Credits low: $%.2f remaining.",
            .ukrainian: "Мало кредитів: залишилось $%.2f.",
        ],

        "settings.providers": [.english: "Providers", .ukrainian: "Провайдери"],
        "settings.providersHint": [
            .english: "Enable providers shown in the menu bar switcher.",
            .ukrainian: "Увімкніть провайдерів для перемикача в menu bar.",
        ],
        "settings.chatgptAccount": [
            .english: "ChatGPT account (Codex + GPT)",
            .ukrainian: "Обліковий запис ChatGPT (Codex + GPT)",
        ],
        "settings.codexAccount": [.english: "Codex account", .ukrainian: "Обліковий запис Codex"],
        "settings.cursorAccount": [.english: "Cursor account", .ukrainian: "Обліковий запис Cursor"],
        "settings.claudeAccount": [.english: "Claude account", .ukrainian: "Обліковий запис Claude"],

        "auth.cursor.title": [.english: "Authorize Cursor", .ukrainian: "Авторизувати Cursor"],
        "auth.cursor.needed": [
            .english: "Cursor is not authorized yet. Use your local Cursor IDE login.",
            .ukrainian: "Cursor ще не авторизований. Використайте локальний вхід Cursor IDE.",
        ],
        "auth.cursor.authorize": [
            .english: "Authorize with Cursor IDE login",
            .ukrainian: "Авторизувати з входом Cursor IDE",
        ],
        "auth.cursor.hint": [
            .english: "Reads your signed-in Cursor session from this Mac (state.vscdb) and stores a token in Keychain.",
            .ukrainian: "Читає сесію Cursor на цьому Mac (state.vscdb) і зберігає токен у Keychain.",
        ],
        "auth.cursor.success": [.english: "Cursor authorized.", .ukrainian: "Cursor авторизовано."],
        "auth.cursor.expired": [
            .english: "Cursor session expired. Authorize again.",
            .ukrainian: "Сесію Cursor завершено. Авторизуйтесь знову.",
        ],
        "auth.cursor.noIDE": [
            .english: "Cursor IDE data not found. Open Cursor and sign in first.",
            .ukrainian: "Дані Cursor IDE не знайдено. Спочатку відкрийте Cursor і увійдіть.",
        ],
        "auth.cursor.noToken": [
            .english: "No Cursor access token found. Sign in to Cursor IDE, then try again.",
            .ukrainian: "Немає токена Cursor. Увійдіть у Cursor IDE і спробуйте знову.",
        ],

        "auth.claude.title": [.english: "Authorize Claude", .ukrainian: "Авторизувати Claude"],
        "auth.claude.needed": [
            .english: "Claude is not authorized yet. Sign in with your Claude.ai account.",
            .ukrainian: "Claude ще не авторизований. Увійдіть через обліковий запис Claude.ai.",
        ],
        "auth.claude.browserLogin": [
            .english: "Sign in with Claude.ai",
            .ukrainian: "Увійти через Claude.ai",
        ],
        "auth.claude.hint": [
            .english: "Opens a secure browser window to Claude.ai and saves the session in Keychain.",
            .ukrainian: "Відкриває безпечне вікно Claude.ai і зберігає сесію в Keychain.",
        ],
        "auth.claude.loginTitle": [
            .english: "Claude.ai login",
            .ukrainian: "Вхід Claude.ai",
        ],
        "auth.claude.loginHint": [
            .english: "Sign in to Claude.ai in the window below.",
            .ukrainian: "Увійдіть у Claude.ai у вікні нижче.",
        ],
        "auth.claude.checkingCookies": [
            .english: "Waiting for login…",
            .ukrainian: "Очікування входу…",
        ],
        "auth.claude.success": [.english: "Claude authorized.", .ukrainian: "Claude авторизовано."],
        "auth.claude.expired": [
            .english: "Claude session expired. Sign in again.",
            .ukrainian: "Сесію Claude завершено. Увійдіть знову.",
        ],
        "auth.claude.noOrg": [
            .english: "Could not find a Claude organization for this account.",
            .ukrainian: "Не знайдено організацію Claude для цього акаунта.",
        ],
        "auth.claude.emptyKey": [
            .english: "Session key is empty.",
            .ukrainian: "Ключ сесії порожній.",
        ],

        "window.plan": [.english: "Plan", .ukrainian: "План"],
        "window.overall": [.english: "Overall", .ukrainian: "Загальне"],
        "window.messages": [.english: "Messages", .ukrainian: "Повідомлення"],
        "window.sonnet": [.english: "Sonnet weekly", .ukrainian: "Sonnet (тиждень)"],
        "window.opus": [.english: "Opus weekly", .ukrainian: "Opus (тиждень)"],

        "settings.danger": [.english: "Danger zone", .ukrainian: "Небезпечна зона"],
        "settings.uninstall": [
            .english: "Uninstall Stack Meter AI…",
            .ukrainian: "Видалити Stack Meter AI…",
        ],
        "settings.uninstallHint": [
            .english: "Removes credentials, settings, caches, notifications, and the app from /Applications (with confirmation). Use this instead of only dragging to Trash.",
            .ukrainian: "Видаляє облікові дані, налаштування, кеші, сповіщення та застосунок з /Applications (з підтвердженням). Краще так, ніж лише в Кошик.",
        ],
        "settings.uninstallTitle": [
            .english: "Uninstall Stack Meter AI?",
            .ukrainian: "Видалити Stack Meter AI?",
        ],
        "settings.uninstallConfirm": [
            .english: "Uninstall completely",
            .ukrainian: "Видалити повністю",
        ],

        "uninstall.intro": [
            .english: "This will permanently:",
            .ukrainian: "Це назавжди:",
        ],
        "uninstall.keychain": [
            .english: "• Delete ChatGPT / Cursor / Claude credentials from Keychain",
            .ukrainian: "• Видалить облікові дані ChatGPT / Cursor / Claude з Keychain",
        ],
        "uninstall.settings": [
            .english: "• Erase Stack Meter AI settings and preferences",
            .ukrainian: "• Видалить усі налаштування Stack Meter AI",
        ],
        "uninstall.caches": [
            .english: "• Remove caches, logs, and other Library leftovers",
            .ukrainian: "• Прибере кеші, логи та інші залишки з Library",
        ],
        "uninstall.notifications": [
            .english: "• Clear notifications and remove the System Settings entry when possible",
            .ukrainian: "• Очистить сповіщення і прибере запис із Системних налаштувань (якщо вдасться)",
        ],
        "uninstall.app": [
            .english: "• Delete Stack Meter AI from /Applications",
            .ukrainian: "• Видалить Stack Meter AI з /Applications",
        ],
        "uninstall.quitOnly": [
            .english: "• Quit the app (drag this copy to Trash if it is not in /Applications)",
            .ukrainian: "• Закриє застосунок (якщо копія не в /Applications — перетягніть її в Кошик)",
        ],
        "uninstall.irreversible": [
            .english: "You can install again later from the DMG. This cannot be undone.",
            .ukrainian: "Пізніше можна знову встановити з DMG. Цю дію неможливо скасувати.",
        ],

        "window.primary": [.english: "Primary", .ukrainian: "Основне"],
        "window.weekly": [.english: "Weekly", .ukrainian: "Тиждень"],
        "window.daily": [.english: "Daily", .ukrainian: "День"],
        "window.monthly": [.english: "Monthly", .ukrainian: "Місяць"],
        "window.5h": [.english: "5-hour", .ukrainian: "5 годин"],
    ]
}
