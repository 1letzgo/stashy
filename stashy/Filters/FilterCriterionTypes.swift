import Foundation

/// Stash `CriterionModifier` values (filters.graphql).
enum StashCriterionModifier: String, CaseIterable, Identifiable, Hashable {
    case equals = "EQUALS"
    case notEquals = "NOT_EQUALS"
    case greaterThan = "GREATER_THAN"
    case lessThan = "LESS_THAN"
    case isNull = "IS_NULL"
    case notNull = "NOT_NULL"
    case includesAll = "INCLUDES_ALL"
    case includes = "INCLUDES"
    case excludes = "EXCLUDES"
    case matchesRegex = "MATCHES_REGEX"
    case notMatchesRegex = "NOT_MATCHES_REGEX"
    case between = "BETWEEN"
    case notBetween = "NOT_BETWEEN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .equals: return tr("equals")
        case .notEquals: return tr("not_equals")
        case .greaterThan: return tr("greater_than")
        case .lessThan: return tr("less_than")
        case .isNull: return tr("is_null")
        case .notNull: return tr("not_null")
        case .includesAll: return tr("includes_all")
        case .includes: return tr("includes")
        case .excludes: return tr("excludes")
        case .matchesRegex: return tr("matches_regex")
        case .notMatchesRegex: return tr("not_matches_regex")
        case .between: return tr("between")
        case .notBetween: return tr("not_between")
        }
    }

    var needsValue: Bool {
        switch self {
        case .isNull, .notNull: return false
        default: return true
        }
    }

    var needsSecondValue: Bool {
        switch self {
        case .between, .notBetween: return true
        default: return false
        }
    }
}

enum FilterCriterionKind: String, CaseIterable, Hashable {
    case string
    case int
    case float
    case boolean
    case date
    case timestamp
    case resolution
    case orientation
    case gender
    case circumcision
    case hierarchicalMulti
    case multi
    case stashID
    case stashIDs
    case phashDistance
    case duplication
    case customFields
    case isMissing
    case hasMarkers
    case hasChapters
    case hierarchicalCount
    case booleanGroup
    case nestedFilter
    case raw

    static func defaultModifiers(for kind: FilterCriterionKind) -> [StashCriterionModifier] {
        switch kind {
        case .string:
            return [.equals, .notEquals, .includes, .excludes, .matchesRegex, .notMatchesRegex, .isNull, .notNull]
        case .int, .float, .hierarchicalCount:
            return [.equals, .notEquals, .greaterThan, .lessThan, .between, .notBetween, .isNull, .notNull]
        case .date:
            return [.equals, .notEquals, .greaterThan, .lessThan, .between, .notBetween, .isNull, .notNull]
        case .timestamp:
            // Stash's MandatoryTimestamp set (created / updated / last played).
            return [.greaterThan, .lessThan, .between, .notBetween]
        case .resolution:
            return [.equals, .notEquals, .greaterThan, .lessThan]
        case .orientation, .gender, .circumcision:
            return [.includes, .excludes, .equals, .notEquals]
        case .hierarchicalMulti, .multi:
            // No `.excludes` — the picker's red state writes the `excludes` list instead, and
            // combining both would mean "not not".
            return [.includes, .includesAll, .isNull, .notNull]
        case .stashID, .stashIDs:
            return [.equals, .notEquals, .includes, .excludes, .isNull, .notNull]
        case .phashDistance:
            return [.equals, .notEquals]
        case .duplication, .boolean, .isMissing, .hasMarkers, .hasChapters, .customFields, .booleanGroup, .nestedFilter, .raw:
            return []
        }
    }

    /// Default empty criterion payload for a newly added field.
    /// `mode` is the entity being filtered (drives `is_missing`'s property list); `nestedMode`
    /// only matters for `.nestedFilter`.
    static func defaultValue(for kind: FilterCriterionKind, nestedMode: StashDBViewModel.FilterMode? = nil, mode: StashDBViewModel.FilterMode = .scenes) -> Any {
        switch kind {
        case .boolean:
            return true
        case .string:
            return ["value": "", "modifier": StashCriterionModifier.includes.rawValue]
        case .int, .float, .hierarchicalCount:
            return ["value": 0, "modifier": StashCriterionModifier.equals.rawValue]
        case .date:
            return ["value": "", "modifier": StashCriterionModifier.equals.rawValue]
        case .timestamp:
            // Complete from the start (today 00:00), so the row is never dropped as half-filled.
            return ["value": FilterTimestampFormat.string(from: Calendar.current.startOfDay(for: Date())),
                    "modifier": StashCriterionModifier.greaterThan.rawValue]
        case .resolution:
            return ["value": "FULL_HD", "modifier": StashCriterionModifier.equals.rawValue]
        case .orientation:
            return ["value": ["LANDSCAPE"]]
        case .gender:
            // `GenderCriterionInput.value` is a single enum — multi-select uses `value_list`.
            return ["value_list": ["FEMALE"], "modifier": StashCriterionModifier.includes.rawValue]
        case .circumcision:
            return ["value": ["CUT"], "modifier": StashCriterionModifier.includes.rawValue]
        case .hierarchicalMulti:
            return ["value": [] as [String], "modifier": StashCriterionModifier.includes.rawValue, "depth": 0]
        case .multi:
            return ["value": [] as [String], "modifier": StashCriterionModifier.includes.rawValue]
        case .stashID, .stashIDs:
            return ["modifier": StashCriterionModifier.notNull.rawValue]
        case .phashDistance:
            return ["value": "", "distance": 0, "modifier": StashCriterionModifier.equals.rawValue]
        case .duplication:
            // `DuplicationCriterionInput { duplicated, distance, phash, url, stash_id, title }` —
            // the type was renamed from `PHashDuplication…`; only `duplicated` is sent by default.
            return ["duplicated": true]
        case .customFields:
            return [["field": "", "value": [] as [Any], "modifier": StashCriterionModifier.equals.rawValue]]
        case .isMissing:
            return FilterFieldCatalog.isMissingOptions(for: mode).first ?? "title"
        case .hasMarkers, .hasChapters:
            return "true"
        case .booleanGroup, .nestedFilter:
            return [String: Any]()
        case .raw:
            return [String: Any]()
        }
    }
}

enum StashResolutionOption: String, CaseIterable, Identifiable {
    case veryLow = "VERY_LOW"
    case low = "LOW"
    case r360p = "R360P"
    case standard = "STANDARD"
    case webHD = "WEB_HD"
    case standardHD = "STANDARD_HD"
    case fullHD = "FULL_HD"
    case quadHD = "QUAD_HD"
    case fourK = "FOUR_K"
    case fiveK = "FIVE_K"
    case sixK = "SIX_K"
    case sevenK = "SEVEN_K"
    case eightK = "EIGHT_K"
    case huge = "HUGE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .veryLow: return "144p"
        case .low: return "240p"
        case .r360p: return "360p"
        case .standard: return "480p"
        case .webHD: return "540p"
        case .standardHD: return "720p"
        case .fullHD: return "1080p"
        case .quadHD: return "1440p"
        case .fourK: return "4K"
        case .fiveK: return "5K"
        case .sixK: return "6K"
        case .sevenK: return "7K"
        case .eightK: return "8K"
        case .huge: return "8K+"
        }
    }
}

enum StashOrientationOption: String, CaseIterable, Identifiable {
    case landscape = "LANDSCAPE"
    case portrait = "PORTRAIT"
    case square = "SQUARE"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .landscape: return tr("landscape")
        case .portrait: return tr("portrait")
        case .square: return tr("square")
        }
    }
}

struct FilterEntityOption: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    /// Only tag search hits carry these; the cached "most used" lists do not.
    var aliases: [String] = []

    func matches(_ term: String) -> Bool {
        name.localizedCaseInsensitiveContains(term)
            || aliases.contains { $0.localizedCaseInsensitiveContains(term) }
    }
}

enum StashGenderOption: String, CaseIterable, Identifiable {
    case male = "MALE"
    case female = "FEMALE"
    case transgenderMale = "TRANSGENDER_MALE"
    case transgenderFemale = "TRANSGENDER_FEMALE"
    case intersex = "INTERSEX"
    case nonBinary = "NON_BINARY"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .male: return tr("male")
        case .female: return tr("female")
        case .transgenderMale: return tr("transgender_male")
        case .transgenderFemale: return tr("transgender_female")
        case .intersex: return tr("intersex")
        case .nonBinary: return tr("non_binary")
        }
    }
}


/// GraphQL `Timestamp` text the app writes ("2024-01-31T13:45", local time, like the web UI).
enum FilterTimestampFormat {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    /// Accepts "2024-01-31T13:45", "2024-01-31 13:45" (web UI) and a bare date.
    static func date(from text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        return formatter.date(from: String(t.prefix(16))) ?? dateOnly.date(from: String(t.prefix(10)))
    }
}
