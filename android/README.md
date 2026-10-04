# stashy for Android

Kotlin/Compose port of the iOS app (same recipe as stede: a parallel native app that mirrors
the iOS code file by file, no KMP). The Stash server is the shared backend; the `.graphql`
documents in `../graphql` are shared 1:1 (wired in as an assets source dir and loaded at
runtime with their fragments, like `GraphQLQueries` on iOS).

**Goal: behave and look as close to the iOS app as possible.** Same tabs, same order, same
labels (English UI like iOS), same defaults, same UserDefaults key strings (`Prefs`), same
layouts and spacing (`Tokens` = iOS `DesignTokens`, `IosTypography` = Dynamic Type sizes).
When porting a screen, read the Swift view first and mirror its structure; name the iOS
counterpart in the KDoc (`/** iOS: SceneCardView … */`).

## Build

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
./gradlew assembleDebug        # APK under ~/Library/Caches/stashy-android/<hash>/app/outputs/apk/debug/
./gradlew testDebugUnitTest
```

Build output lives outside iCloud (`~/Library/Caches/stashy-android/<checkout hash>`), one
directory per checkout so git worktrees don't collide.

Debug server for the emulator: put into `android/local.properties` (never committed)

```
stashy.debug.server=https://stashytest.gole.tz
stashy.debug.apiKey=…
```

The debug build then starts connected (`ServerConfigManager.seedDebugServer`).

## Layout (`app/src/main/java/de/letzgo/stashy/`)

| Android | iOS |
|---|---|
| `data/Prefs.kt` (`Prefs`, `Secrets`) | UserDefaults, `KeychainManager` |
| `data/ServerConfig.kt`, `ServerConnection.kt` | `ServerConfig`, `ServerConfigManager`, `StashConnectionProbe`, `LoginAuthHelper` |
| `data/Net.kt` (`Net.client`, `Net.signed`, `LocalHosts`) | `StashSessionFactory`, `StashTrustDelegate`, `signedURL` |
| `data/GraphQL.kt` (`GraphQL`, `GraphQLQueries`) | `GraphQLClient`, `GraphQLQueries` |
| `data/Models.kt` | models in `StashDBViewModel.swift` |
| `data/Repositories.kt` (`FindFilter`, `findPage`) | `stashy/Repositories`, `StashDBViewModel` fetches |
| `data/Plus.kt` (`StashyPlus.isUnlocked`) | `StashyPlusManager` |
| `data/Downloads.kt` | `DownloadManager` |
| `ui/Theme.kt` (`Appearance`, `Theme.palette`, `Tokens`, `StashyColors`) | `AppearanceManager`, `Color.app*`, `DesignTokens` |
| `ui/Chrome.kt` (`stashyGlass`, `GlassIconButton`, `GlassCapsule`, `GlassBadge`, `ChromeChip`, `SectionHeader`, `BackPill`) | `SharedChromeComponents`, `StashyTopNavStrip`, chrome |
| `ui/Icons.kt` (`SF.*`) | SF Symbols — add mappings there |
| `ui/Nav.kt` (`Nav`, `Screen`, `MainTab`, `CatalogTab`) | `TabManager`, `NavigationCoordinator` |
| `ui/AppShell.kt` | `MainTabView` (floating glass tab bar + search circle) |
| `ui/Paging.kt` (`PagedList`) | infinite-scroll pattern of the list views |
| `ui/catalog/` (`CatalogController`, `CatalogScaffold`, `CatalogFloatingBar`) | `CatalogsView`, `ScenesView`, `PerformersView` …, `CatalogChrome`, `FloatingCatalogBar` |
| `ui/filter/` (`CatalogFilterSortSheet`, `FilterCriteriaEditor`, `FilterPickerOptionsStore`) | `ListCatalogFilterSortSheets`, `Filters/FilterCriteriaEditorView`, `FilterPickerOptionsStore` |
| `data/FilterMapper.kt`, `FilterFields.kt`, `Filters.kt`, `Sorting.kt` | `FilterMapper`, `FilterFieldCatalog`, `FilterCriteriaDocument`, `*SortOption`, presets |
| `data/CatalogPrefs.kt`, `CatalogRepositories.kt`, `SavedFilters.kt` | catalog facade over `TabManager` (sorts, default filters, card columns), list fetches, `SavedFiltersStore` (iOS `viewModel.savedFilters`, shared by catalogs, dashboard and Settings) |
| `ui/components/` (`SceneCard`, `EntityCards.kt`) | `SceneCardView`, `PerformerCardView`, `StudioCardView`, `TagCardView`, `GalleryCardView`, `GroupCardView`, `ImageThumbnailCard`, `MarkerCardView` |
| `ui/home/` | `HomeView` (dashboard) |
| `ui/scene/` | `SceneDetailView`, `SceneDetail/` (`SceneAiSubtitles` = AI half of `ScenePlayerExtrasController`) |
| `ui/player/ai/` | `stashy/Subtitles/` (`LiveTranscriber`, `CaptionTranslator`, `TranscodeAudioSource`, pure `CaptionTimeline`), `SubtitleTargetLanguage`, `SceneTeleprompterMode` |
| `ui/detail/` | Performer/Studio/Tag/Gallery/Group detail |
| `ui/player/` (`StashPlayer`, `VideoSurface`, `ScenePlayerSurface`, `TimeBar`, `PreviewPlayer`/`PreviewPlayerPool`, `PlaybackService`, `PlayerWindow`) | `Playback/` (AetherEngine → Media3 ExoPlayer, see below), `SubtitleController`, `SceneScrubSprites` |
| `data/SceneEditing.kt`, `data/SceneEvents.kt` | scene mutations of `StashDBViewModel`, scene `NotificationCenter` posts + `sceneLiveUpdates` (`SceneEvent.applyTo`, collected by `CatalogController` and `DashboardStore`) |
| `ui/feeds/` | `ReelsView` |
| `ui/tools/` | `ToolsView` + tools, stashy+ paywall |
| `data/TabConfigs.kt`, `data/TabManager.kt` | `TabManager` — the one store of tabs (order/visibility → Home chip strip), session/default/detail sorts, default filters, card columns, `HomeRowsConfig`, channels, Feeds modes, playback/subtitle keys; `defaultsVersion` + `lastDefaultsChange` = iOS `DefaultSortChanged` / `DefaultFilterChanged` |
| `data/Security.kt` (`PasscodeVault`, `SecurityManager`) | `SecurityManager`, Keychain PIN (`app_passcode_v1`) |
| `data/DashboardRepository.kt` | dashboard/search/server-task fetches of `StashDBViewModel`, `SavedFiltersCache` |
| `ui/settings/`, `ui/setup/`, `ui/search/` | `Settings/`, `ToolsServerView`, `PasscodeEntryView`, setup wizard, `UniversalSearchView` |
| `tv/` | `stashyTV` |

## Android TV (`tv/`)

Same APK, own entry: `tv/TvActivity` (Leanback launcher; `MainActivity` forwards to it when
`UiModeManager` reports a television). Mirrors `stashyTV` file by file with Compose for TV
(`androidx.tv:tv-material`): `TvMain` = `TVMainTabView` (sidebar Search · Home · Library · Settings,
one back stack per entry in `TvNav`, Back on a tab root focuses the sidebar), `TvDashboard`,
`TvCatalogs` (`TVCatalogGrid` + the seven catalogs, tvOS sort labels in `TvSortLabels`),
`TvDetail` / `TvSceneDetail`, `TvImageViewer`, `TvSearch`, `TvSettings` (two-column pages,
same keys as tvOS incl. `tv_pin_*`), `TvServerSetup`, `TvPlayer` (`TVAetherPlayerView` on the
shared `StashPlayer`: D-pad seek with 10/30/60 s acceleration and sprite scrub, Down = options
panel with audio/subtitles/markers, channels with Up Next and hold ▲/▼), `TvChannel` (stashy+).
Sizes are tvOS points halved (`pt()`: 1920 pt ≙ 960 dp). Pure logic lives in `TvLogic.kt` (tested).

## Conventions

- Catalog deep links (dashboard "›" headers, stats tiles, Search "Show All"): `Nav.openCatalog(tab, sort, search, noDefaultFilter)`;
  the catalog root consumes the request (`CatalogController.applyRequest`).
- Navigation: push a `Screen` implementation (`Nav.push(SceneDetailScreen(id))`); each tab has
  its own back stack; `hidesTabBar = true` for full-screen content.
- Content under the floating chrome: top padding `catalogTopPadding()` on catalog roots,
  bottom padding `TabBarClearance` on every scrolling root.
- Colours only from `Theme.palette`, `Appearance.tint`, `StashyColors` — no ad-hoc colours.
- Network only through `GraphQL` / `Net.client` (auth headers, LAN self-signed TLS); media URLs
  through `Net.signed()` (adds `apikey=` like iOS).
- Playback: iOS plays the original file of any codec with its FFmpeg engine (AetherEngine).
  Android's `StashPlayer` plays the original with Media3 ExoPlayer over `Net.client` and, when
  the device can't (unrecognised container, decoder failure, no supported video/audio track, no
  first frame in 20 s), falls back like the iOS ladder to Stash's `stream.m3u8` HLS transcode,
  then `stream.mp4?start=` — the player shows a "Transcode" tag and a toast.
- AI Subtitles (stashy+, `ui/player/ai/`, `ui/scene/SceneAiSubtitles.kt`; iOS `stashy/Subtitles/`,
  `ScenePlayerExtras` AI half). Same menu ("AI Subtitles: …" right after the player's Subtitles,
  Off / English / my language, "Spoken in this scene" picker saved to `custom_fields.language`,
  download rows), same keys (`stashy_ai_cc_preferred_mode`, `stashy_subtitle_target_language`),
  same gating (locked row → paywall). Engine choices:
  - **Speech: Vosk** (`com.alphacephei:vosk-android`, Kaldi, Apache-2.0). Android has no system
    recognizer that takes a PCM stream and returns word timings (`SpeechRecognizer` is mic-only on
    most devices, no timestamps); whisper.cpp would need the NDK (not installed) and is far slower
    on phones. Vosk is a prebuilt AAR, runs several × realtime on the small models, returns word
    times, and has small (~40–50 MB) per-language models — downloaded only after the user taps
    "Download" (like iOS speech assets) into `filesDir/speech-models/` (`SpeechModelCatalog`,
    `SpeechModelStore`). No model for a language → no captions (never another language's model).
  - **Audio: the iOS prefetcher** (`TranscodeAudioSource` + `ChunkPlanner`): Stash's 240p
    `stream.mp4?start=…&resolution=LOW` in byte-budgeted ~45 s chunks via `Net.client`, decoded
    with MediaExtractor/MediaCodec → 16 kHz mono (`PcmResampler`), fed to one continuous
    recognizer up to ~1 min ahead of the playhead (`FeedScheduler`: 2 s pre-roll + 58 s lead,
    restart when 12 s behind or on a seek outside the transcribed range). Playback itself never
    switches source. The iOS tiers "AVAssetReader on the original" and "engine PCM tap" are not
    ported; the transcode tier works for every container/codec.
  - **Cues** (`CaptionTimeline.kt`): Vosk finals are cut into sentences at pauses / 110 chars /
    7 s, timed like iOS (`flushPendingSentence` reading hold, previous cue cut at the next start,
    selection only moves forward) and drawn by the normal `SubtitleOverlay`
    (`StashPlayer.displayedSubtitleText`, live channel `beginLiveCaptions/pushLiveCaption`).
  - **Translation: ML Kit on-device** (`com.google.mlkit:translate`, `CaptionTranslator`), packs
    downloaded only after "Download XX language pack"; ML Kit reports no byte progress, so the
    menu shows "Downloading … language pack…". Like iOS, only AI captions are translated (server
    WebVTT tracks are shown as they are).
  - Size: native libs add ~26 MB installed / ~10 MB download per ABI (arm64: libtranslate_jni
    16 MB, libvosk 10 MB); the universal APK carries all four ABIs (~100 MB more). Ship an AAB
    (or set `abiFilters`) for releases. Settings › stashy+ › "Delete downloaded language packs".
- Not ported: AI Motion and device control (Handy, Intiface, LoveSpouse) — Play policy.
