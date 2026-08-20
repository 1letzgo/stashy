# stashy

A native **Stash** client for **iOS** and **tvOS** built with **SwiftUI** — fast, no built-in tracking, and wired directly to your Stash server.

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
- **Xcode** (recommended: current stable release).
GraphQL documents live under `graphql/` and are loaded at runtime.

## Platforms & distribution

| Platform | App Store |
|----------|-----------|
| **iOS** | [stashy](https://apps.apple.com/us/app/stashy/id6754876029) |
| **tvOS** | Early beta |


## Roadmap (excerpt)

- Bring tvOS closer to iOS feature parity
- Performance and memory for very large libraries

## Known limitations

- **tvOS** does not include every iOS feature.


## Third-party

**Match** (Hot-or-Not–style rating function) is **inspired by** **[Ascension](https://github.com/Servbot91/Ascension/tree/main)** — the Sakoto fork of Hot or Not for Stash. Stashy aims to stay **compatible with the same custom-field / DB entries** used by that plugin ecosystem, but **matchmaking and scoring algorithms** in the app **differ** from Ascension’s server-side behaviour.
