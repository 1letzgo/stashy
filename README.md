# stashy

A native **Stash** client for **iOS** and **tvOS** built with **SwiftUI**, plus a native **Android** / **Android TV** app built with **Jetpack Compose** — fast, no built-in tracking, and wired directly to your Stash server.

## Features (current repo)

- **Home & catalogue** — configurable dashboard (rows, statistics, lists), scenes, performers, studios, galleries, images, tags, groups, markers.
- **Feeds** — vertical swipeable clip feed, optional “Social” from performer detail; image/video timelines with filters.
- **Downloads** — download scenes for offline playback.
- **Playback** — streaming with selectable quality (per server / for Reels); iOS scene detail uses KSPlayer (AV-backed) for device sync.
- **Devices** — TheHandy, **Intiface** / Buttplug including **FunScript** in the player.
- **Search** — global search across server content.
- **Settings** — multiple servers, API keys (Keychain on iOS), appearance, default sort/filter per area, tab visibility and order.

## Privacy

**No** analytics or tracking user data — no third-party trackers in the app, no app-assigned user IDs.

## Requirements

- A running **[Stash](https://github.com/stashapp/stash)** server (GraphQL API as used by the app).
- **Xcode** (recommended: current stable release) for iOS / tvOS.
- **JDK 17** + Android SDK for Android / Android TV (min. Android 8.0, API 26) — see [`android/README.md`](android/README.md).

GraphQL documents live under `graphql/`, are shared by all platforms and loaded at runtime.

## Platforms & distribution

| Platform | Status |
|----------|--------|
| **iOS** | [App Store](https://apps.apple.com/us/app/stashy/id6754876029) |
| **tvOS** | [App Store](https://apps.apple.com/us/app/stashy/id6754876029) |
| **Android** | In development — no public release yet |
| **Android TV** | In development — no public release yet |

### Want to test Android / Android TV?

There is no public release yet. If you'd like to try the Android or Android TV build early, join us on **[Discord](https://discord.gg/DMxEFaVzUM)** and ask for a test build.


## Roadmap (excerpt)

- First public release for Android / Android TV
- Performance and memory for very large libraries

## Known limitations

- **Android / Android TV** are pre-release builds and do not yet cover every iOS feature.


## Third-party

**Match** (Hot-or-Not–style rating function) is **inspired by** **[Ascension](https://github.com/Servbot91/Ascension/tree/main)** — the Sakoto fork of Hot or Not for Stash. Stashy aims to stay **compatible with the same custom-field / DB entries** used by that plugin ecosystem, but **matchmaking and scoring algorithms** in the app **differ** from Ascension’s server-side behaviour.
