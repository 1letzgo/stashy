# stashy

A native **Stash** client for **iOS** and **tvOS** built with **SwiftUI**, plus a native **Android** / **Android TV** app built with **Jetpack Compose** — fast, no ads, no analytics, and wired directly to your Stash server.

## Features (current repo)

- **Home & catalogue** — configurable dashboard (rows, statistics, lists), scenes, performers, studios, galleries, images, tags, groups, markers.
- **Feeds** — vertical swipeable clip feed, optional “Social” from performer detail; image/video timelines with filters.
- **Downloads** — download scenes for offline playback.
- **Playback** — streaming with selectable quality (per server / for Reels); iOS / tvOS play original files directly via AetherEngine (FFmpeg-based, incl. AV1 / HEVC), Android uses Media3 ExoPlayer.
- **Devices** — TheHandy, **Intiface** / Buttplug including **FunScript** in the player.
- **Search** — global search across server content.
- **Settings** — multiple servers, API keys (Keychain on iOS), appearance, default sort/filter per area, tab visibility and order.

## Privacy

- **No** ads, analytics or tracking SDKs. Your library, server address and API key never reach the developer — all traffic goes directly between your device and your Stash server.
- **stashy+ purchases** are verified through **[RevenueCat](https://www.revenuecat.com/privacy)**. RevenueCat receives a random, anonymous app user ID, the store receipt / purchase token, app version, OS, device model and IP address — not linked to your name or email and not used for advertising. Payment itself is handled only by Apple / Google.
- **Optional devices:** with The Handy enabled, the funscript of the current scene is uploaded to Handy's cloud (handyfeeling.com) together with your connection key. Intiface / Buttplug (local network) and Love Spouse (Bluetooth) stay local.
- **On-device AI** (subtitles, translation, AI Motion) runs locally; the models are downloaded once from Apple, Google ML Kit or alphacephei.com (Vosk), which see your IP address.

Full details: [Privacy Policy](https://stashy.shelf.am/stashy-datenschutz.html).

## Requirements

- A running **[Stash](https://github.com/stashapp/stash)** server (GraphQL API as used by the app).
- **Xcode** (recommended: current stable release) for iOS / tvOS.
- **JDK 17** + Android SDK for Android / Android TV (min. Android 8.0, API 26) — see [`android/README.md`](android/README.md).

GraphQL documents live under `graphql/`, are shared by all platforms and loaded at runtime.

## Platforms & distribution

| Platform | Status |
|----------|--------|
| **iOS** | [App Store](https://apps.apple.com/us/app/stashy/id6754876029) |
| **tvOS** | In App Review |
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

### Services

| Service | Used for | Platforms |
|---------|----------|-----------|
| [RevenueCat](https://www.revenuecat.com) | stashy+ purchase verification | iOS, tvOS, Android (Play) |
| Apple App Store / Google Play Billing | Payments for stashy+ | iOS, tvOS / Android |
| [The Handy](https://www.thehandy.com) (handyfeeling.com) | Device sync — funscript upload, optional | iOS |
| [Intiface](https://intiface.com) / Buttplug | Device sync over the local network, optional | iOS |
| Love Spouse | Device sync over Bluetooth, optional | iOS |
| Apple Speech / Translation, [Google ML Kit](https://developers.google.com/ml-kit), [Vosk](https://alphacephei.com/vosk/) | On-device AI subtitles and translation (one-time model download) | iOS / Android |

### Libraries

- **iOS / tvOS:** [AetherEngine](https://github.com/superuser404notfound/AetherEngine) (player, FFmpeg / dav1d), [RevenueCat](https://github.com/RevenueCat/purchases-ios-spm), [SwiftDraw](https://github.com/swhitty/SwiftDraw) (SVG).
- **Android:** Jetpack Compose & Compose for TV, [Media3 ExoPlayer](https://developer.android.com/media/media3), [OkHttp](https://square.github.io/okhttp/), [Coil](https://coil-kt.github.io/coil/), kotlinx.serialization / coroutines, WorkManager, AndroidX Biometric & Security, [RevenueCat](https://github.com/RevenueCat/purchases-android), [Vosk](https://alphacephei.com/vosk/), [ML Kit Translate](https://developers.google.com/ml-kit/language/translation).

### Credits

**Match** (Hot-or-Not–style rating function) is **inspired by** **[Ascension](https://github.com/Servbot91/Ascension/tree/main)** — the Sakoto fork of Hot or Not for Stash. Stashy aims to stay **compatible with the same custom-field / DB entries** used by that plugin ecosystem, but **matchmaking and scoring algorithms** in the app **differ** from Ascension’s server-side behaviour.
