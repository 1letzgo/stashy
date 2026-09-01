# AI Tags — tagger model

The Core ML tagger for **AI Tags** (stashy+) is **not** shipped inside the app. The app
reads a manifest from this repository, downloads the model, verifies its checksum,
compiles it on device and runs it offline from then on.

Default manifest URL (overridable in Settings → stashy+ → AI Tags):

```
https://raw.githubusercontent.com/1letzgo/stashy/main/models/aitagger-manifest.json
```

## Artifact requirements

* Either container:
  * `"format": "mlmodel"` — a single-file `.mlmodel`.
  * `"format": "mlpackage-aar"` — an ML Program `.mlpackage` packed with Apple Archive.
    Modern coremltools emits `.mlpackage` (a directory), and Apple Archive is the only
    unpacker iOS ships with, so pack it:
    ```bash
    aa archive -d tagger-v1.mlpackage -o tagger-v1.aar
    ```
  Both are compiled on device with `MLModel.compileModel(at:)`.
* Image input; the app feeds `CGImage` frames through Vision, so any input size works.
* Output either
  * a Core ML **classifier** (its own class labels are used), or
  * a **multi-label vector** — then `labels` in the manifest must list the labels in
    output order.
* Host the file where a plain GET works (GitHub Releases is fine; raw files over 100 MB
  are not).

## Manifest format

See `aitagger-manifest.example.json`. Fields:

| field | required | meaning |
|---|---|---|
| `id` | yes | storage key; changing it installs alongside, not over |
| `name` | yes | shown in Settings |
| `version` | yes | highest version in the list wins; drives "update available" |
| `url` | yes | direct download of the `.mlmodel` |
| `sha256` | yes | `shasum -a 256 model.mlmodel` — a mismatch discards the download |
| `format` | no | `mlmodel` (default) or `mlpackage-aar` |
| `sizeBytes` | no | for the progress bar when the server sends no length |
| `labels` | for multi-label | labels in output order |
| `aliases` | no | model label → your Stash tag names, for wording that differs |
| `threshold` | no | minimum confidence per label, default `0.35` |
| `crop` | no | `scaleFit` (default), `centerCrop`, `scaleFill` |
| `license` | no | shown in Settings — put the model's attribution here |

## Label mapping

Model labels are matched against the tag names of the connected Stash server:
`aliases` first, then a normalized name match (case, `_`, `-` and punctuation ignored).
**Labels with no matching tag are dropped** — suggesting a tag that does not exist would
only fail on accept. Add the tag in Stash, or map it via `aliases`.
