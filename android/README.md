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
stashy.debug.server=http://192.168.x.y:9999
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
| `ui/catalog/` | `CatalogsView`, `ScenesView`, `PerformersView` … |
| `ui/components/` | `SceneCardView` and other shared cards |
| `ui/home/` | `HomeView` (dashboard) |
| `ui/scene/` | `SceneDetailView`, `SceneDetail/` |
| `ui/detail/` | Performer/Studio/Tag/Gallery/Group detail |
| `ui/player/` (`StashPlayer`, `VideoSurface`, `ScenePlayerSurface`, `TimeBar`, `PreviewPlayer`/`PreviewPlayerPool`, `PlaybackService`, `PlayerWindow`) | `Playback/` (AetherEngine → Media3 ExoPlayer, see below), `SubtitleController`, `SceneScrubSprites` |
| `data/SceneEditing.kt`, `data/SceneEvents.kt` | scene mutations of `StashDBViewModel`, scene `NotificationCenter` posts |
| `ui/feeds/` | `ReelsView` |
| `ui/tools/` | `ToolsView` + tools, stashy+ paywall |
| `ui/settings/`, `ui/setup/`, `ui/search/` | `Settings/`, setup wizard, `UniversalSearchView` |
| `tv/` | `stashyTV` |

## Conventions

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
- Not ported: AI Motion and device control (Handy, Intiface, LoveSpouse) — Play policy.
