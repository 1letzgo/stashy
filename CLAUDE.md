# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Stashy is a native iOS/tvOS SwiftUI app for browsing and managing a Stash media server (GraphQL API). Multi-server support, custom filtering, video playback, device sync, and feed-style browsing (StashTok/Feeds). Premium features are gated behind `stashy+` (StoreKit).

## Build Commands

### iOS Target
```bash
xcodebuild -project stashy.xcodeproj -scheme stashy -destination 'generic/platform=iOS' build
```

### tvOS Target
```bash
xcodebuild -project stashy.xcodeproj -scheme stashyTV -destination 'generic/platform=tvOS' build
```

### Tests
No test target is wired into the Xcode project. `stashyTests/` holds Swift Testing files (`InfrastructureTests.swift`: StashTrustDelegate, GraphQL retry, PaginatedLoader generation, AppLog redaction) ready to attach to a future target. Verification = the two builds above + manual testing on device/simulator.

## Architecture Overview

### Core Patterns

**Singleton managers** — cross-cutting state, all `.shared`:
- `AppearanceManager` — theme/tint colors, O-counter icon choice (UserDefaults)
- `ServerConfigManager` — multi-server config storage + active server
- `TabManager` — tab visibility/order, dashboard rows, reels mode config
- `KeychainManager` — API key storage (iOS only; tvOS falls back to UserDefaults)
- `GraphQLClient` — actor-based GraphQL client (async/await + completion APIs)
- `ImageCacheManager` — dual-tier image cache (memory + disk, server-scoped)
- `stashy/Managers/`: `SecurityManager` (passcode/biometric lock), `SessionTimelineLoader`, `OCountHeatmapLoader`, `StashyPlusManager` (entitlements), `AppIconManager`, `LoginAuthHelper`, `StashSyncManager` (+ `StashVideoSyncManager`), `VideoAnalysisManager`, `SceneAudioTrackController`, `SubtitleController`
- Nested in `StashDBViewModel.swift`: `DownloadManager`, `HandyManager`, `ButtplugManager`, `LoveSpouseManager`, `SceneStreamsRAMCache`; `StoreManager` lives in `Settings/SettingsView.swift`

**Navigation**: `NavigationCoordinator` is an `@EnvironmentObject` passed app-wide. Handles tab selection, deep links, navigation-stack resets (UUID-based `.id()` modifiers), cross-tab jumps (scene → performer), and remote injection of filter/sort state.

**Main ViewModel**: `StashDBViewModel` (~12k lines, `@MainActor`) is the app's data hub — server status (staggered init: Filters → Statistics → Ready), statistics, saved filters, scene metadata, O-counter with optimistic updates, plus the nested managers above. Its nested enums (`FilterMode`, `SceneSortOption`, `PerformerSortOption`, `SavedFilter`, …) are referenced throughout the UI layer, so it is a de-facto shared namespace, not just a view model.

**There are no per-domain ViewModels.** Screens either instantiate their own `StashDBViewModel` (e.g. `CatalogsView` keeps one warm for all catalog sub-tabs) or use a filter/sort controller (below).

**Repository layer** (`stashy/Repositories/`): `SceneRepository`, `PerformerRepository`, `StudioRepository`, `GalleryRepository`, `TagRepository` — thin GraphQL fetch wrappers. Coverage is partial; most fetching still lives in `StashDBViewModel`.

**Filter/sort controllers** (`DetailLinkedCatalogControllers.swift`): `DetailLinkedPerformersFilterModel`, `DetailLinkedImagesFilterModel`, etc. — `ObservableObject`s holding live-filter chips, sort option, saved filter, and local presets for a *scope* (`.catalogRoot`, `.studio(id)`, `.tag(id)`, `.performer(id)`, …). Hosted by the parent view so state survives child remounts. Shared preset/chip encodings live in `ListCatalogFilterSortModels.swift`; the sheets in `ListCatalogFilterSortSheets.swift`.

**Filtering (two layers)**: quick chips are the primary surface; the full Stash criteria editor sits one level deeper.
- Chips live in the catalog sheets (`ListCatalogFilterSortSheets.swift`, `SceneLiveFilterSheet` in `ScenesView.swift`) and produce a chip fragment (`activeLiveFilterDict`).
- `stashy/Filters/` holds the advanced editor, mirroring Stash's own model: `FilterCriterionTypes.swift` (`CriterionModifier` + criterion kinds and their default payloads), `FilterFieldCatalog.swift` (per-`FilterMode` field descriptors), `FilterCriteriaDocument.swift` (an editable `object_filter` with sanitizing), `FilterCriteriaEditorView.swift` (one row per criterion kind), `AdvancedCriteriaCard.swift` (the "Advanced" row in every filter sheet plus its editor sheet), `FilterPickerOptionsStore.swift` (shared, cached studio/tag/group/performer options — never create a `StashDBViewModel` per criterion row), and `FiltersToolsView.swift` (Tools → Filters).
- Merge rule (`FilterCriteriaDocument.merged(with:)`): advanced criteria are the base, active chips are layered on top, so a chip always wins for its own key.
- Selecting a server filter loads its criteria into the document (`loadCriteriaDocument(from:)`), and the fetch then passes `filter: fetchBaseFilter` — `nil` while the document holds the copy, the filter itself while the document is still empty. Without that, the server filter would resurrect criteria the user just edited away.
- The advanced editor commits on `Done`, never per keystroke; text fields commit on submit/focus loss. Never wire `onChange:` of a criterion row straight to a refetch.
- Adding a new filterable field = add a `FilterFieldDescriptor` to the right catalog array and make sure its kind serializes to the shape Stash's `*FilterType` expects (`GenderCriterionInput` uses `value_list`, `duplicated` is `PHashDuplicationCriterionInput`, …).
- Saving goes through `StashDBViewModel.saveFullObjectFilter` (preserves `ui_options.stashy.liveFragment` unless explicitly replaced); renaming goes through `renameSavedFilter`, which never rewrites criteria.

**Pagination**: `stashy/Utilities/PaginatedLoader.swift` — generic `PaginatedLoader<T>` with `loadInitial()`, `loadMore()`, `refresh()`, `reset()` and per-type static builders. Currently unreferenced by app code; treat as available infrastructure, not the established pattern.

### Data Flow

1. **Network**: `GraphQLClient`
   - Actor-based for thread safety
   - Shared `StashTrustDelegate` (GraphQLClient.swift) accepts self-signed certs for localhost/private IPs + `gole.tz`; used by GraphQLClient, ImageCacheManager, and `StashNetworking.session`
   - `withDatabaseRetry` auto-retries "database is locked" (execute, executeRaw, performMutation)
   - Typed envelope validation: errors with null data are fatal, partial errors tolerated
   - Requests outside GraphQLClient use `stashRequest(to:config:)` + `StashNetworking.session`
2. **Logging**: `AppLog.debug` / `AppLog.error` (SharedUtilities.swift) gate output behind DEBUG; `AppLog.redacted` masks secrets. Never use raw `print()` or log API keys.
3. **Image loading**: `ImageCacheManager` — memory 300 MB / 300 items, disk ~30-day TTL scoped per server ID (prevents leakage on server switch). Cache keys strip timestamp params but keep `width`/`height`/`size`. Use `CustomAsyncImage`. Cleanup every 4h.
4. **GraphQL queries**: two coexisting sources
   - `.graphql` files in `graphql/` (folder reference — new files are picked up automatically), loaded via `GraphQLQueries.loadQuery(named:)` / `queryWithFragments(...)` (thread-safe caching), with `fragment_*.graphql` for reusable field sets
   - Inline `static let` mutation/query constants in `GraphQLQueries.swift` (~38 extracted from StashDBViewModel)
5. **Server config**: `ServerConfig` (Codable, UserDefaults) — name, address, port, protocol, streaming quality. API keys in Keychain on iOS. Server-specific settings use the `"<key>_<serverID>"` suffix pattern. Switching servers clears URLCache + image disk cache, posts `"ServerConfigChanged"`, and ViewModels call `GraphQLClient.shared.cancelAllRequests()`.

### Platform Differences

Shared code with `#if !os(tvOS)` guards. Many iOS-only files guard their *entire* contents, so a new iOS-only file still compiles into the tvOS target harmlessly — but tvOS UI is a separate hand-written surface in `stashyTV/` (`TV*` views, focus-based navigation, remote input, simplified layouts). tvOS lacks Keychain, haptics, UIKit scene delegates, and gesture-heavy components.

`PocketSVG` (SPM) is linked to the **stashyTV target only**.

## Key Components

- **Tabs**: `AppTab` enum in `TabManager.swift` (dashboard, catalogue, scenes, images, galleries, performers, studios, tags, groups, markers, media, reels, stashline, downloads, tools, stashyPlus, search, settings). Visibility/order configurable. `catalogue` ("Home") hosts sub-tabs via `CatalogsView.CatalogsTab`.
- **Home/Dashboard**: `stashy/Home/` — `HomeRowView`, `HomeSceneCardView`, `HomeStatisticsRowView`, `HomeChannelsRowView`; rows configured in `Settings/DashboardSettingsView.swift`.
- **Tools tab** (`ToolsView` in `MainTabView.swift`): dispatches to `OCountHeatmapToolsView`, `SessionTimelineToolsView`, `FiltersToolsView`, `HotOrNotToolsView` (Match), `RateMeToolsView`, `TopListsToolsView`. When stashy+ is locked, the `stashyPlus` paywall tab replaces `tools`.
- **Feeds / StashTok** (`ReelsView.swift`, ~5.8k lines): modes Scenes / Markers / Clips, infinite scroll via `ScrollViewReader`, per-mode sorts, mute tied to headphone detection, full-screen zoom + rotation. Known fragility: autoplay/selection races around `currentVisibleSceneId` and `autoSelectFirstItem` — change with care.
- **Reels feeds data**: initial fetches are single-flight (`*InitialInflightKey` in StashDBViewModel); paging has safety valves (failure streaks, no-progress detection, preview chase cap, restore budget in ReelsView); stream resolution is prefetched after page 1 and never cached when empty.
- **Scene detail**: `SceneDetailView.swift` + `stashy/SceneDetail/Components/` (`SceneVideoPlayerCard`, `SceneHeatmapCard`, `ScenePerformersCard`, `SceneTagsCard`, `SceneStudioCard`, `SceneGalleriesCard`, `SceneGroupsCard`).
- **Video playback**: `FullScreenVideoPlayer` (UIViewRepresentable over AVPlayerLayer); quality selection (Original/4K/1080p/720p/480p/240p) with separate settings for normal playback vs Feeds.
- **Subtitles / transcription** (`stashy/Subtitles/`): live on-device transcription + translation (`SceneLiveTranscriptionController`, `SceneCaptionTranslator`, `SceneTranscodeAudioPrefetcher`).
- **Device sync**: `StashSyncManager` ("AI Motion", stashy+ only) drives haptic/device channels from on-device video analysis (`VideoAnalysisManager`); intensity is published through Combine subjects, deliberately **not** `@Published`, to avoid ~30 Hz SwiftUI rebuilds that restack `AVPlayerLayer` over menus. Plus `HandyManager`, `ButtplugManager` (Intiface/funscript), `LoveSpouseManager`.
- **stashy+ gating**: `StashyPlusManager.isUnlockedNow` / product IDs in `Managers/StashyPlusManager.swift`. Subscriptions + lifetime IAP + legacy paid purchase unlock; tips never do. Gate new premium features through this manager, never an ad-hoc flag.
- **Chrome**: `FloatingCatalogBar.swift` (`FloatingActionBar`, `CatalogFloatingChromeState` — floating bar hides when no server or empty-list-with-error), `StashyTopNavStrip.swift`, `SharedChromeComponents.swift`.
- **Design system**: `DesignTokens.swift` (spacing, corner radius `DesignTokens.CornerRadius.card` = 12pt, shadows, animation presets, `DesignTokens.Chrome.*`), view extensions `.cardShadow()` / `.subtleShadow()` / `.floatingShadow()`, `HapticManager`, `ToastManager`.

## Important Patterns

### Adding/Removing Files
The `stashy` target uses classic Xcode groups — update `project.pbxproj` in 4 sections (`PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`). The `stashyTV` target uses a filesystem-synchronized group (auto-pickup). `graphql/` is a folder reference.

### Adding a New Setting
1. Define the UserDefaults key (use the `_<serverID>` suffix if server-specific)
2. Add UI in the matching section under `stashy/Settings/`
3. Update the owning singleton (`TabManager`, `AppearanceManager`, …) if one exists
4. Decide whether it must reset on `"ServerConfigChanged"`

### Adding a New GraphQL Query
1. Add a `.graphql` file to `graphql/` (folder reference — no pbxproj edit needed)
2. Load via `GraphQLQueries.loadQuery(named:)` or `queryWithFragments(...)`
3. Put the fetch in the relevant Repository when one exists

### Supporting a New Content Type
1. Codable model (models mostly live in `StashDBViewModel.swift` / `SharedUtilities.swift`)
2. Repository in `stashy/Repositories/`
3. View in `stashy/`, plus a `DetailLinked*FilterModel` if it needs filter/sort
4. `AppTab` / `CatalogsTab` entry in `TabManager.swift` / `CatalogsView.swift` if it needs a tab
5. GraphQL queries + fragments, and `FilterFieldCatalog` fields if it should be filterable

### Notifications
- `"ServerConfigChanged"` — server switched, reset all data
- `"AuthError401"` — posted by GraphQLClient on 401
- Background URL session completion (downloads)

### UserDefaults Keys
- Active server: `"stashy_server_config"`; server list: `"stashy_saved_servers"`
- Per-server: `"<key>_<serverID>"` (dashboard rows, tab visibility, …)
- Tint: `kTintColorRed`, `kTintColorGreen`, `kTintColorBlue`, `kTintColorAlpha`

## SSL and Local Servers
`GraphQLClient` and `ImageCacheManager` share a URLSession delegate that accepts self-signed certs for localhost/private IP ranges and whitelists `gole.tz` (test server) — required for local Stash servers.

## Migration and Backward Compatibility
`ServerConfig` decodes the legacy format (connectionType, ipAddress, domain, useHTTPS) and migrates to the unified one (serverAddress, port, serverProtocol). API keys auto-migrate from UserDefaults to Keychain on iOS.

## Notes on Comments
Existing code mixes English and German comments (older files skew German). Match the surrounding file.
