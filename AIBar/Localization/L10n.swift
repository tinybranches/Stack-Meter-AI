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
        "quit.confirmTitle": [
            .english: "Quit Stack Meter AI?",
            .ukrainian: "Вийти зі Stack Meter AI?",
        ],
        "quit.confirmMessage": [
            .english: "Usage tracking in the menu bar will stop until you open the app again.",
            .ukrainian: "Відстеження лімітів у меню-барі зупиниться, доки ви знову не відкриєте застосунок.",
        ],
        "common.status": [.english: "Status", .ukrainian: "Статус"],

        "instance.alreadyTitle": [
            .english: "Already running",
            .ukrainian: "Уже запущено",
        ],
        "instance.alreadyBody": [
            .english: "Stack Meter AI %@ is already running in the menu bar. This second copy will quit.",
            .ukrainian: "Stack Meter AI %@ уже працює в меню-барі. Ця друга копія зараз закриється.",
        ],
        "instance.olderTitle": [
            .english: "Older version is running",
            .ukrainian: "Запущена старіша версія",
        ],
        "instance.olderBody": [
            .english: "An older Stack Meter AI (%@) is still running in the menu bar. Quit it before opening this update — or quit it now from this dialog.",
            .ukrainian: "У меню-барі досі працює старіша Stack Meter AI (%@). Закрийте її перед відкриттям цього оновлення — або завершіть її зараз із цього вікна.",
        ],
        "instance.newerTitle": [
            .english: "Newer version is running",
            .ukrainian: "Запущена новіша версія",
        ],
        "instance.newerBody": [
            .english: "A newer Stack Meter AI (%@) is already running. This older copy will quit.",
            .ukrainian: "Уже працює новіша Stack Meter AI (%@). Ця старіша копія зараз закриється.",
        ],
        "instance.quitOlder": [
            .english: "Quit older version",
            .ukrainian: "Закрити старішу версію",
        ],
        "instance.ok": [
            .english: "OK",
            .ukrainian: "Гаразд",
        ],

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

        "auth.title": [.english: "Authorize Codex", .ukrainian: "Авторизувати Codex"],
        "auth.needed": [
            .english: "Codex is not authorized in Stack Meter AI yet.",
            .ukrainian: "Codex ще не авторизований у Stack Meter AI.",
        ],
        "auth.expired": [
            .english: "Session expired. Sign in again to continue.",
            .ukrainian: "Сесію завершено. Увійдіть знову, щоб продовжити.",
        ],
        "auth.rateLimitedTemp": [
            .english: "Temporarily rate limited while fetching usage.",
            .ukrainian: "Тимчасово обмежено під час отримання використання.",
        ],
        "auth.chatgpt.title": [.english: "Authorize Codex", .ukrainian: "Авторизувати Codex"],
        "auth.chatgpt.needed": [
            .english: "Stack Meter needs its own Codex authorization (Safari login is separate). If Codex CLI is already signed in on this Mac, import that session.",
            .ukrainian: "Stack Meter потрібна своя авторизація Codex (вхід у Safari — окремо). Якщо Codex CLI уже залогінений на цьому Mac — імпортуйте цю сесію.",
        ],
        "auth.localHint.codex": [
            .english: "Safari/Chrome cookies are not shared. Use Codex CLI import if you already ran `codex login`, or sign in once in the app window.",
            .ukrainian: "Cookies Safari/Chrome не спільні з цим застосунком. Якщо вже робили `codex login` — імпортуйте CLI; або увійдіть один раз у вікні застосунку.",
        ],
        "auth.localHint.cursor": [
            .english: "Uses the Cursor app login on this Mac (not the website). Sign in to the Cursor IDE first, then authorize here — or we import it automatically on launch when possible.",
            .ukrainian: "Береться вхід із застосунку Cursor на цьому Mac (не з сайту). Спочатку увійдіть у Cursor IDE, потім авторизуйте тут — або ми підхопимо сесію автоматично при запуску.",
        ],
        "auth.localHint.claude": [
            .english: "Browser cookies are not shared. If Claude Desktop is signed in on this Mac, import that session — or sign in once in the app window.",
            .ukrainian: "Cookies браузера не спільні. Якщо Claude Desktop уже залогінений на цьому Mac — імпортуйте цю сесію; або увійдіть один раз у вікні застосунку.",
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
            .english: "Codex uses your ChatGPT account. If in-app Google login fails, run `codex login` then use “Authorize with Codex CLI login”.",
            .ukrainian: "Codex використовує обліковий запис ChatGPT. Якщо Google у вікні не входить — виконайте `codex login`, потім «Авторизувати з входу Codex CLI».",
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
        "auth.chatgpt.cliPrimary": [
            .english: "Most reliable: run `codex login` in Terminal, then import the session here. In-app Google login often shows a blank page.",
            .ukrainian: "Найнадійніше: у Терміналі виконайте `codex login`, потім імпортуйте сесію тут. Вхід Google у вікні часто дає білий екран.",
        ],
        "auth.chatgpt.openSafari": [
            .english: "Open ChatGPT in Safari",
            .ukrainian: "Відкрити ChatGPT у Safari",
        ],
        "auth.chatgpt.copyCLI": [
            .english: "Copy `codex login`",
            .ukrainian: "Копіювати `codex login`",
        ],
        "auth.chatgpt.cliCopied": [
            .english: "Copied `codex login` — paste it in Terminal, finish login, then import.",
            .ukrainian: "Скопійовано `codex login` — вставте в Термінал, завершіть вхід, потім імпортуйте.",
        ],
        "auth.chatgpt.loadingPage": [
            .english: "Loading ChatGPT…",
            .ukrainian: "Завантаження ChatGPT…",
        ],
        "auth.chatgpt.loadFailed": [
            .english: "The login page didn’t load (common with Google in this window). Reload, or use Codex CLI import above.",
            .ukrainian: "Сторінка входу не завантажилась (типово для Google у цьому вікні). Перезавантажте або скористайтесь імпортом Codex CLI вище.",
        ],
        "auth.chatgpt.reload": [
            .english: "Reload",
            .ukrainian: "Перезавантажити",
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
            .english: "Codex account (ChatGPT login)",
            .ukrainian: "Обліковий запис Codex (вхід ChatGPT)",
        ],
        "settings.codexAccount": [.english: "Codex account", .ukrainian: "Обліковий запис Codex"],
        "settings.cursorAccount": [.english: "Cursor account", .ukrainian: "Обліковий запис Cursor"],
        "settings.claudeAccount": [.english: "Claude account", .ukrainian: "Обліковий запис Claude"],

        "auth.cursor.title": [.english: "Authorize Cursor", .ukrainian: "Авторизувати Cursor"],
        "auth.cursor.needed": [
            .english: "Cursor is not authorized yet. Sign in to the Cursor app on this Mac, then authorize (or wait for auto-import on next launch).",
            .ukrainian: "Cursor ще не авторизований. Увійдіть у застосунок Cursor на цьому Mac, потім авторизуйте (або зачекайте автоімпорт при наступному запуску).",
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
            .english: "Claude is not authorized yet. Import Claude Desktop login, or sign in with Claude.ai.",
            .ukrainian: "Claude ще не авторизований. Імпортуйте вхід Claude Desktop або увійдіть через Claude.ai.",
        ],
        "auth.claude.browserLogin": [
            .english: "Authorize Claude…",
            .ukrainian: "Авторизувати Claude…",
        ],
        "auth.claude.fromDesktop": [
            .english: "Authorize with Claude Desktop",
            .ukrainian: "Авторизувати з Claude Desktop",
        ],
        "auth.claude.noDesktop": [
            .english: "Claude Desktop not found. Install/sign in to Claude.app, or use the browser login.",
            .ukrainian: "Claude Desktop не знайдено. Встановіть/увійдіть у Claude.app або використайте вхід через браузер.",
        ],
        "auth.claude.noDesktopSession": [
            .english: "No Claude Desktop session found. Open Claude.app and sign in, then try again.",
            .ukrainian: "Сесію Claude Desktop не знайдено. Відкрийте Claude.app, увійдіть, потім спробуйте знову.",
        ],
        "auth.claude.keychainDenied": [
            .english: "macOS blocked access to Claude Safe Storage. Click Allow when prompted, then try again.",
            .ukrainian: "macOS заблокував доступ до Claude Safe Storage. Натисніть Allow у запиті, потім спробуйте знову.",
        ],
        "auth.claude.hint": [
            .english: "Prefers Claude Desktop session on this Mac. Browser cookies alone are not shared; otherwise use the in-app Claude.ai login.",
            .ukrainian: "Спочатку береться сесія Claude Desktop на цьому Mac. Cookies браузера самі по собі не підходять; інакше — вхід Claude.ai у вікні застосунку.",
        ],
        "auth.claude.loginTitle": [
            .english: "Claude.ai login",
            .ukrainian: "Вхід Claude.ai",
        ],
        "auth.claude.loginHint": [
            .english: "Claude.ai blocks in-app browsers. Use Claude Desktop import or paste the sessionKey cookie from Safari.",
            .ukrainian: "Claude.ai блокує вбудований браузер. Імпортуйте Claude Desktop або вставте cookie sessionKey із Safari.",
        ],
        "auth.claude.noWebViewExplain": [
            .english: "The embedded browser stays blank on purpose — Claude.ai/Cloudflare blocks it. Use one of the options below.",
            .ukrainian: "Вбудований браузер лишається білим навмисно — Claude.ai/Cloudflare його блокує. Скористайтесь одним із варіантів нижче.",
        ],
        "auth.claude.stepDesktopTitle": [
            .english: "1. Recommended — Claude Desktop",
            .ukrainian: "1. Рекомендовано — Claude Desktop",
        ],
        "auth.claude.stepDesktopBody": [
            .english: "If Claude.app is signed in on this Mac, import that session. macOS may ask to allow “Claude Safe Storage” — choose Allow.",
            .ukrainian: "Якщо Claude.app уже залогінений на цьому Mac — імпортуйте сесію. macOS може попросити доступ до «Claude Safe Storage» — натисніть Allow.",
        ],
        "auth.claude.stepSafariTitle": [
            .english: "2. Or paste sessionKey from Safari",
            .ukrainian: "2. Або вставте sessionKey із Safari",
        ],
        "auth.claude.stepSafariBody": [
            .english: "Open Claude.ai in Safari → sign in → Develop/Web Inspector → Storage → Cookies → copy the sessionKey value (starts with sk-ant-).",
            .ukrainian: "Відкрийте Claude.ai у Safari → увійдіть → Web Inspector → Storage → Cookies → скопіюйте значення sessionKey (починається з sk-ant-).",
        ],
        "auth.claude.checkingCookies": [
            .english: "Waiting for login…",
            .ukrainian: "Очікування входу…",
        ],
        "auth.claude.desktopPrimary": [
            .english: "Most reliable: authorize from Claude Desktop on this Mac.",
            .ukrainian: "Найстабільніше: авторизація з Claude Desktop на цьому Mac.",
        ],
        "auth.claude.openSafari": [
            .english: "Open Claude.ai in Safari",
            .ukrainian: "Відкрити Claude.ai у Safari",
        ],
        "auth.claude.safariHint": [
            .english: "After signing in, copy the sessionKey cookie and paste it below.",
            .ukrainian: "Після входу скопіюйте cookie sessionKey і вставте нижче.",
        ],
        "auth.claude.pasteKey": [
            .english: "Paste sessionKey (sk-ant-…)",
            .ukrainian: "Вставити sessionKey (sk-ant-…)",
        ],
        "auth.claude.useKey": [
            .english: "Authorize",
            .ukrainian: "Авторизувати",
        ],
        "auth.claude.success": [.english: "Claude authorized.", .ukrainian: "Claude авторизовано."],
        "auth.claude.expired": [
            .english: "Claude session expired. Sign in again.",
            .ukrainian: "Сесію Claude завершено. Увійдіть знову.",
        ],
        "auth.claude.noOrg": [
            .english: "No Claude chat organization found for this session. Open claude.ai once, then sign in again here.",
            .ukrainian: "Для цієї сесії не знайдено Claude chat-організацію. Відкрийте claude.ai один раз, потім увійдіть тут знову.",
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
        "window.5h": [.english: "Current session", .ukrainian: "Поточна сесія"],
        "window.oauthApps": [.english: "OAuth / Claude Code", .ukrainian: "OAuth / Claude Code"],
        "window.cowork": [.english: "Cowork weekly", .ukrainian: "Cowork (тиждень)"],
    ]
}
