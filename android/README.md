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
| `ui/catalog/` (`CatalogController`, `CatalogScaffold`, `CatalogTopActions`, `CatalogFilterFab`) | `CatalogsView`, `ScenesView`, `PerformersView` …, `CatalogChrome`, `FloatingCatalogBar` |
| `ui/filter/` (`CatalogFilterSortSheet`, `FilterCriteriaEditor`, `FilterPickerOptionsStore`) | `ListCatalogFilterSortSheets`, `Filters/FilterCriteriaEditorView`, `FilterPickerOptionsStore` |
| `data/FilterMapper.kt`, `FilterFields.kt`, `Filters.kt`, `Sorting.kt` | `FilterMapper`, `FilterFieldCatalog`, `FilterCriteriaDocument`, `*SortOption`, presets |
| `data/CatalogPrefs.kt`, `CatalogRepositories.kt`, `SavedFilters.kt` | catalog facade over `TabManager` (sorts, default filters, card columns), list fetches, `SavedFiltersStore` (iOS `viewModel.savedFilters`, shared by catalogs, dashboard and Settings) |
| `ui/NativeCards.kt` (`NativeCard`, `NativeMediaLabel`), `ui/components/` (`SceneCard`, `EntityCards.kt`) | `SceneCardView`, `PerformerCardView`, `StudioCardView`, `TagCardView`, `GalleryCardView`, `GroupCardView`, `ImageThumbnailCard`, `MarkerCardView` |
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
- Pushed screens (Android look, Material 3): `NativeTopBar(title)` instead of the iOS Back pill
  and floating glass buttons; content top padding `nativeTopBarPadding()` (detail pages:
  `detailTopPadding(hasTabs)`, which adds the section `NativeTabStrip`). Actions follow one
  pattern (`ui/NativeActions.kt`): up to three frequent actions as `TopBarAction` icons
  (download state, sort, favorite, share …; active = `Appearance.tint`), sort pickers as
  `TopBarMenuAction` (`DropdownMenu` anchored to the icon), rarer actions (Edit, card columns,
  Delete, Sync newest N, Set as performer image) in the "⋮" `TopBarOverflowMenu`. Detail pages
  build all of it through `DetailTopBar` (sections → tab strip, `ChromeSlot`s → icons or
  overflow via `inOverflow`); no floating bottom slot bars. Media viewers use a transparent
  `NativeTopBar`; their on-image controls (O-counter, rating, mute/play) stay overlay buttons.
- Catalog roots (Home tab, Android look): the iOS floating glass slot bar is gone. "Filter &
  sort" is a Material `ExtendedFloatingActionButton` (`CatalogFilterFab`) bottom-end, 16 dp above
  the NavigationBar (collapses to the icon while scrolling down, badge dot = active filter); the
  other slots (columns toggle, quick sort menu, contextual) are app-bar icons in the trailing
  slot of the Home `NativeTabStrip` (`CatalogScaffold` publishes them via `CatalogTopActions`;
  menus are anchored `DropdownMenu`s like `TopBarMenuAction`, active = `Appearance.tint`) — the
  same icon/menu vocabulary as `ui/NativeActions.kt` on pushed screens. With a single visible
  catalog the strip stays when the catalog has such icons. Active search = Material `InputChip`
  (tap clears). Grids: 16 dp margins, 12 dp gutters (`CatalogGridGutter`); bottom padding
  `TabBarClearance + FloatingBarClearance`.
- Cards (Android look, `ui/NativeCards.kt`): every card is a Material `ElevatedCard`
  (`NativeCard`, 12 dp corners, 1 dp elevation on `Theme.palette.secondaryBackground`) and takes
  an `onClick` (ripple) — don't wrap cards in `noRippleClickable`. Labels over images are
  `NativeMediaLabel` (translucent surface container, `labelSmall`/`labelMedium`, 8 dp corners;
  studio logos on a dark scrim); `GlassBadge`/`CardPill`/`CaptionPill` delegate to it. Titles use
  `NativeType` (titleMedium on media, titleSmall under logos). Long-press previews
  (`ScenePreviewOnHold`) observe the pointer inside the card and keep working with the ripple.
- Dashboard: Material section headers (titleLarge + "See all" `TextButton` for rows that open a
  catalog), rows as `LazyRow`s styled like the Material uncontained carousel (16 dp margins, 8 dp
  gaps; the hero row snaps and uses 28 dp `NativeHeroShape` items). Not `material3.carousel`:
  in material3 1.3.1 `CarouselState` exposes no current item (the hero backdrop follows the
  focused card) and carousels take no item keys (live scene updates). Statistics are tonal
  Material cards (stat colour at 14–22 % over the surface, icon in the full colour).
- Content under the chrome: top padding `catalogTopPadding()` on catalog roots,
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

## Distribution flavors & self-update

| Flavor | stashy+ | Updates | Build |
|---|---|---|---|
| `sideload` | included (`PLUS_INCLUDED`) | self-update from `https://buntes.am/app/stashy.apk` (`data/AppUpdate.kt`) | `./gradlew assembleSideloadRelease` |
| `play` | Google Play Billing | Play Store (no install permission, no self-update — Play policy) | `./gradlew bundlePlayRelease` |

`versionCode` = number of git commits (`git rev-list --count HEAD`), so every build from a newer
commit is higher. The self-update needs only the APK on the server: a HEAD request compares
`ETag`/`Last-Modified` with the install time; after the download the APK's own `versionCode`
decides whether it is offered for installation. Checked on resume (every 6 h at most) and via
Settings → App → Check for Updates. Upload a new build simply by replacing `stashy.apk` on the
server — always signed with the same key (`~/Library/Application Support/stashy-signing/`).
