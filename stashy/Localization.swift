//
//  Localization.swift
//  stashy
//
//  Shared-key localization. Every UI text has one key that iOS, tvOS, macOS and Android share
//  (Android: `R.string.<key>`). Keys and translations are kept in Tolgee (project "stashy",
//  tools/l10n/README.md); `Localizable.xcstrings` is pulled from there.
//

import Foundation
import Combine
import SwiftUI

/// The localized text for `key`. Arguments fill `%@` / `%1$@` in order and are shown as text,
/// exactly like a string interpolation (`"\(value)"`).
/// Without arguments the text is not run through `String(format:)`, so a `%` from Tolgee shows as
/// it is whether or not the export escaped it as `%%`.
func tr(_ key: String, _ args: Any...) -> String {
    let format = AppLanguage.text(for: key)
    guard !args.isEmpty else { return format.replacingOccurrences(of: "%%", with: "%") }
    let texts: [CVarArg] = args.map { String(describing: $0) as NSString }
    return String(format: format, arguments: texts)
}

/// The language of stashy's own texts: the device's language when stashy has it, English otherwise.
/// One switch in Settings ("Use stashy in English", offered when the device is not English anyway)
/// forces English. A change applies at once: `tr()` reads the new bundle and `LanguageRefreshing`
/// rebuilds the interface. System texts (alerts, date pickers) follow from the next start, through
/// `AppleLanguages`. Apple TV has no switch and stays English.
enum AppLanguage {
    static let storageKey = "app_language"
    static let systemValue = "system"
    static let defaultValue = "en"

    /// Languages with a translation in Tolgee, named in their own language.
    static let options: [(code: String, name: String)] = [
        ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("fr", "Français"),
        ("it", "Italiano"), ("nl", "Nederlands"), ("sv", "Svenska"), ("da", "Dansk"),
        ("nb", "Norsk bokmål"), ("pl", "Polski"), ("pt-BR", "Português (Brasil)"),
        ("tr", "Türkçe"), ("ru", "Русский"), ("ja", "日本語"),
        ("ko", "한국어"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ]

    /// The stored choice: "en" (the switch is on) or "system". A language picked in the former
    /// picker counts as "system".
    static var stored: String {
        #if os(tvOS)
        return defaultValue
        #else
        return UserDefaults.standard.string(forKey: storageKey) == defaultValue ? defaultValue : systemValue
        #endif
    }

    /// The switch "Use stashy in English".
    static var usesEnglish: Bool { stored == defaultValue }

    /// The language stashy speaks on this device without the switch.
    static var deviceLanguage: String { resolve(systemValue) }

    /// Whether the switch is offered: not on a device that gets English anyway (unless it is on).
    static var offersEnglishSwitch: Bool { usesEnglish || deviceLanguage != defaultValue }

    /// Switches every text to `code` right away and rebuilds the interface.
    static func select(_ code: String) {
        UserDefaults.standard.set(code, forKey: storageKey)
        applyPreferredLanguages()
        state.withLock { $0 = State(code: code) }
        DispatchQueue.main.async { AppLanguageStore.shared.languageDidChange() }
    }

    /// System texts (alerts, pickers, dates) follow the same language from the next start on.
    static func applyPreferredLanguages() {
        if stored == systemValue {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([stored], forKey: "AppleLanguages")
        }
    }

    static func name(for code: String) -> String {
        code == systemValue ? tr("device_language") : (options.first { $0.code == code }?.name ?? code)
    }

    /// For SwiftUI's own formatting (dates, numbers) inside the app.
    static var locale: Locale {
        Locale(identifier: state.withLock { $0.resolved })
    }

    /// The device's languages, from the global domain: the app's own `AppleLanguages` override
    /// (set while the switch is on) hides them in the standard defaults and in
    /// `Locale.preferredLanguages` until the next start.
    private static var deviceLanguages: [String] {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return global ?? Locale.preferredLanguages
    }

    /// "system" → the best of stashy's languages for the device, English when none fits.
    private static func resolve(_ code: String) -> String {
        guard code == systemValue else { return code }
        let codes = options.map(\.code)
        let match = Bundle.preferredLocalizations(from: codes, forPreferences: deviceLanguages).first
        return match.flatMap { codes.contains($0) ? $0 : nil } ?? defaultValue
    }

    private struct State {
        let code: String
        let resolved: String
        let bundle: Bundle
        init(code: String) {
            self.code = code
            resolved = AppLanguage.resolve(code)
            bundle = AppLanguage.lproj(resolved) ?? AppLanguage.english
        }
    }

    private static func lproj(_ code: String) -> Bundle? {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private static let english: Bundle = lproj("en") ?? .main
    private static let state = LockedValue(State(code: stored))
    private static let missing = "\u{1}"

    /// Whether `text` is the text of `key` in any of the app's languages (or an older English
    /// wording of it), e.g. a default title stored while another language was active.
    static func isTranslation(_ text: String, ofKey key: String) -> Bool {
        let fold: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let target = fold(text)
        if target.isEmpty { return false }
        let all = translationCache.withLock { cache -> Set<String> in
            if let known = cache[key] { return known }
            let texts = Set(options.compactMap { option -> String? in
                guard let bundle = lproj(option.code) else { return nil }
                return fold(bundle.localizedString(forKey: key, value: missing, table: nil))
            })
            cache[key] = texts
            return texts
        }
        return all.contains(target)
    }

    /// Every language's text of a key, folded; the bundles never change while the app runs.
    private static let translationCache = LockedValue([String: Set<String>]())

    /// The text in the active language, English when it has no translation yet.
    static func text(for key: String) -> String {
        let bundle = state.withLock { $0.bundle }
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        if value != missing && value != key { return value }
        return english.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Small lock around a value (`tr()` is called from any thread).
final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

/// Tells the interface that the app language changed.
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()
    @Published private(set) var revision = 0
    func languageDidChange() { revision += 1 }
}

/// Root wrapper: hands the chosen language to SwiftUI's own formatting. The tab content rebuilds
/// itself on a change (`MainTabView`), open sheets such as the setup wizard re-render in place.
struct LanguageRefreshing<Content: View>: View {
    @ObservedObject private var store = AppLanguageStore.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, AppLanguage.locale)
    }
}
