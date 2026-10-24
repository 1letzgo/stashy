# stashy settings transfer — JSON format v1

One file moves servers, settings, default filters, dashboard rows, tab layout, watchlist and
the rest of the app's preferences between devices and platforms (iOS, iPadOS, macOS, Android).
iOS/macOS and Android store preferences under the **same key names** (`UserDefaults` /
`SharedPreferences`, per-server keys as `<key>_<serverID>`), so a file written on one platform
imports on the other: keys a platform doesn't use are stored and simply ignored.

```json
{
  "format": "stashy-settings",
  "version": 1,
  "exportedAt": "2026-10-24T18:00:00Z",
  "app": { "platform": "ios", "version": "3.3.7", "build": "410" },
  "includesSecrets": false,
  "activeServerId": "FE189A7C-F11D-435E-979F-AC8CB93B11A5",
  "servers": [
    {
      "id": "FE189A7C-F11D-435E-979F-AC8CB93B11A5",
      "name": "My Stash",
      "serverAddress": "192.168.1.10",
      "port": "9999",
      "serverProtocol": "HTTP",
      "subpath": null,
      "apiKey": "…",
      "customHeaders": [{ "id": "…", "name": "X-Token", "value": "…" }]
    }
  ],
  "settings": [
    { "key": "isPiPEnabled", "type": "bool", "value": true },
    { "key": "playerSkipSeconds", "type": "double", "value": 10 },
    { "key": "HomeRowsConfig_FE189A7C-…", "type": "json", "value": [ … ] }
  ]
}
```

## Fields

- `format` must be `stashy-settings`; `version` is `1`. Importers reject other formats and
  newer major versions.
- `servers`: ids are uppercase UUID strings and are kept on import, so every
  `<key>_<serverID>` setting still belongs to its server. `serverProtocol` is `HTTP` / `HTTPS`.
  `apiKey` and `customHeaders` are only present when `includesSecrets` is `true` (the user
  opted in at export); otherwise they are omitted.
- `activeServerId`: the server to activate after import (when it is in `servers`).
- `settings`: one entry per preference.
  - `bool`, `int`, `double`, `string`: plain values.
  - `json`: a JSON array or object that the app keeps *encoded* (iOS: `Data` holding JSON,
    Android: a JSON string). Importers store it the platform's way.
  - `array`, `dictionary`: native plist collections (iOS only writes these; Android stores
    them as JSON strings).
  - Unknown `type` values are skipped.

## Never exported / never imported

Purchases and licenses (`stashy_plus_*`, `totalTipsCount`, StoreKit/RevenueCat bookkeeping,
license keys), the app lock (`kBiometricsEnabled`, `kAutoLockOnBackground`, passcode),
caches and transient state (`cached*`, `mini_player_last_*`, `SK*`), the raw server lists
(`stashy_server_config`, `stashy_saved_servers*`, carried in `servers` instead) and anything
the OS writes into the app's domain (`NS*`, `Apple*`, `com.apple.*`, `WebKit*`).

## Import semantics

Merge, never wipe: servers are added or updated by id, settings in the file overwrite the
same keys, everything else stays. Values whose key already exists locally keep the local
storage type (e.g. a `double` arriving for an Android float key). The app reloads its
settings after import; some screens only pick everything up after a restart.
