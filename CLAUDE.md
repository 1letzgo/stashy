# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Stashy is a native iOS/tvOS SwiftUI application for browsing and managing a Stash media server. It supports multiple server configurations, custom filtering, video playback, and features like StashTok (reels-style viewing).

## Build Commands

### iOS Target
```bash
xcodebuild -project stashy.xcodeproj -scheme stashy -destination 'generic/platform=iOS' build
```

### tvOS Target
```bash
xcodebuild -project stashy.xcodeproj -scheme stashyTV -destination 'generic/platform=tvOS' build
```

### Running Tests
```bash
# Run all tests
xcodebuild test -project stashy.xcodeproj -scheme stashy -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -project stashy.xcodeproj -scheme stashy -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:stashyTests/SpecificTestClass
```

## Architecture Overview

### Core Patterns

**Singleton Managers**: The app uses shared singleton instances for cross-cutting concerns:
- `AppearanceManager.shared` - Manages theme/tint colors and O-counter icon selection, persists to UserDefaults
- `ServerConfigManager.shared` - Multi-server config storage, active server selection
- `TabManager.shared` - Tab visibility, ordering, dashboard rows, and reels mode configuration
- `KeychainManager.shared` - Secure API key storage (iOS only, not tvOS)
- `GraphQLClient.shared` - Centralized network client with SSL handling for local servers
- `ImageCacheManager.shared` - Dual-tier image cache (memory + disk, server-scoped)

**Navigation**: `NavigationCoordinator` is passed as an `@EnvironmentObject` throughout the app. It manages:
- Tab selection and deep linking
- Navigation stack resets (via UUID-based `.id()` modifiers)
- Cross-tab navigation (e.g., opening a performer from a scene detail)
- Remote state injection for filters/sorts

**Main ViewModel**: `StashDBViewModel` is a large (~6000 lines) `@MainActor` class that handles:
- Server connectivity and status (staggered init: Filters → Statistics → Ready)
- Statistics fetching and saved filters from Stash server
- Scene metadata (performers, studios, tags, galleries)
- O-counter (play count) tracking with optimistic updates
- Nested managers: `DownloadManager`, `HandyManager` (TheHandy device), `ButtplugManager` (Intiface/funscript)

**Domain ViewModels**: Specialized view models in `stashy/ViewModels/`:
- `ScenesViewModel` - Scene browsing, filtering, sorting
- `PerformersViewModel` - Performer listing
- `GalleriesViewModel` - Gallery browsing
- `StudiosViewModel` - Studio filtering and browsing
- `TagsViewModel` - Tag management

**Repository Layer**: `stashy/Repositories/` contains data access objects:
- `SceneRepository`, `PerformerRepository`, `StudioRepository`, `GalleryRepository`, `TagRepository`, `FilterRepository`
- These encapsulate GraphQL queries and data fetching logic

**Pagination**: `stashy/Utilities/PaginatedLoader.swift` provides a generic `PaginatedLoader<T>` with `loadInitial()`, `loadMore()`, `refresh()`, and `reset()` methods. Includes convenience static builders for each content type.

### Data Flow

1. **Network Layer**: `GraphQLClient` handles all GraphQL requests
   - Actor-based design for thread safety
   - Custom `URLSessionDelegate` for self-signed SSL certificates on local networks
   - Automatic retry logic for "database is locked" errors (common with SQLite-backed Stash)
   - Supports async/await, Combine, and completion handler APIs

2. **Image Loading**: `ImageCacheManager` provides dual-tier caching:
   - Memory cache: 300 MB, 300 items max
   - Disk cache: ~30-day TTL, server-scoped (separate cache per server ID to prevent data leakage on server switch)
   - Stable cache key normalization: strips timestamp params but retains `width`/`height`/`size` params
   - `CustomAsyncImage` view component for easy image loading with fallbacks
   - Auto-cleanup runs every 4 hours

3. **GraphQL Queries**: Stored as `.graphql` files in `graphql/` directory
   - Loaded at runtime via `GraphQLQueries.loadQuery(named:)`
   - Thread-safe in-memory caching after first load (concurrent DispatchQueue)
   - Contains fragment files (`fragment_*.graphql`) for reusable field sets
   - `queryWithFragments` method for composing queries with fragments

4. **Server Configuration**:
   - Multi-server support via `ServerConfig` (Codable, persisted in UserDefaults)
   - Each server has: name, address, port, protocol (HTTP/HTTPS), streaming quality settings
   - API keys stored in Keychain (iOS) with UserDefaults fallback
   - Server-specific settings use suffix pattern: `"key_\(serverID)"`
   - Switching servers posts `"ServerConfigChanged"` notification, triggering app-wide data reset

5. **Settings Architecture** (refactored 2026-02-06):
   - All settings views live in `stashy/Settings/`
   - Main entry point: `SettingsView.swift` (replaces old ServerConfigView)
   - Modular sections: `ServerListSection`, `PlaybackSettingsSection`, `ContentSettingsSection`
   - Separate views: `ServerDetailView`, `DashboardSettingsView`, `ReelsModeSettingsView`, `AppearanceSettingsView`, etc.

### Platform Differences

**iOS vs tvOS**: Most code is shared with `#if !os(tvOS)` guards for iOS-only features:
- Keychain access (tvOS uses UserDefaults for API keys)
- UIKit integrations (SceneDelegate, AppDelegate)
- Haptic feedback (`HapticManager`)
- Certain UI components (e.g., complex gestures)

**tvOS-specific**: Separate target (`stashyTV`) with:
- Focus-based navigation
- Remote control inputs
- Simplified UI optimized for 10-foot viewing

## Key Components

### Tab System
- Defined in `TabManager.swift` as `AppTab` enum
- Configurable visibility and ordering via TabManager
- Home tab contains sub-tabs (Dashboard, Scenes, Performers, etc.) accessed via `catalogueSubTab`

### Home/Dashboard
- Customizable rows defined in `DashboardSettingsView`
- Each row can show: Recent scenes, Performers, Studios, or filtered scene lists
- Backed by `HomeRowView` which fetches data based on row configuration

### StashTok / Reels (`ReelsView.swift`, ~2100 lines)
- Supports 3 modes: Scenes, Markers (bookmarks), Clips (images)
- Infinite scroll with native `ScrollViewReader`
- Mute state tied to headphone detection (`isHeadphonesConnected()`)
- Per-mode sort options; full-screen media zoom with rotation support

### Video Playback
- Custom `FullScreenVideoPlayer` (UIViewRepresentable wrapping AVPlayerLayer)
- Supports quality selection (Original, 4K, 1080p, 720p, 480p, 240p)
- Separate quality settings for normal playback vs StashTok (reels)

### Design System
- `DesignTokens.swift` defines spacing, corner radius, shadows, and animation presets
- Consistent card styling with `DesignTokens.CornerRadius.card` (12pt)
- View extensions: `.cardShadow()`, `.subtleShadow()`, `.floatingShadow()`
- Haptic feedback via `HapticManager`
- Toast notifications via `ToastManager`

## Important Patterns

### Adding/Removing Files
When modifying Xcode project structure, update `project.pbxproj` in 4 sections:
1. `PBXBuildFile` - Build file references
2. `PBXFileReference` - File system references
3. `PBXGroup` - Logical file tree
4. `PBXSourcesBuildPhase` - Compile sources for target(s)

### Server Config Changes
When ServerConfigManager saves a new active config:
1. Clears URLCache and `ImageCacheManager` disk cache to prevent auth/data leakage
2. Posts `"ServerConfigChanged"` notification
3. ViewModels observe this and call `GraphQLClient.shared.cancelAllRequests()`
4. UI resets to clean state

### Notifications Used
- `"ServerConfigChanged"` - Server switched, reset all data
- `"AuthError401"` - Unauthorized, posted by GraphQLClient on 401 response
- Background URL session completion (for downloads)

### UserDefaults Keys
- Active server: `"stashy_server_config"`
- Server list: `"stashy_saved_servers"`
- Per-server settings: `"<key>_<serverID>"` (e.g., dashboard rows, tab visibility)
- Tint color: `kTintColorRed`, `kTintColorGreen`, `kTintColorBlue`, `kTintColorAlpha`

## Common Tasks

### Adding a New Setting
1. Define UserDefaults key (use server ID suffix if server-specific)
2. Add UI in appropriate Settings view (e.g., `ContentSettingsSection` for content-related)
3. If using a manager, update the singleton (e.g., `TabManager`, `AppearanceManager`)
4. Consider whether setting needs to reset on server change

### Adding a New GraphQL Query
1. Create `.graphql` file in `graphql/` directory
2. Add to Xcode project (must be in Copy Bundle Resources build phase)
3. Load via `GraphQLQueries.loadQuery(named: "yourQuery")`
4. Consider adding to appropriate Repository class

### Supporting a New Content Type
1. Define data model (Codable struct)
2. Create Repository in `stashy/Repositories/`
3. Create ViewModel in `stashy/ViewModels/`
4. Add view in `stashy/` (e.g., `MyContentView.swift`)
5. Update TabManager if it needs a dedicated tab
6. Add GraphQL queries/fragments

## SSL and Local Servers

Both `GraphQLClient` and `ImageCacheManager` include custom URLSession delegates that:
- Accept self-signed certificates for localhost/private IP ranges
- Whitelist `gole.tz` domain (test server)
- Essential for local Stash server connectivity

## Migration and Backward Compatibility

- ServerConfig supports legacy format (connectionType, ipAddress, domain, useHTTPS)
- Decodes old configs and migrates to new unified format (serverAddress, port, serverProtocol)
- API keys auto-migrate from UserDefaults to Keychain on iOS

## Testing

Test targets:
- `stashyTests` - Unit tests
- `stashyUITests` - UI automation tests

No extensive test coverage currently exists; most testing is manual.
