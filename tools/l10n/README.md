# Localization

Every UI text of stashy has one **key**, shared by iOS / tvOS / macOS and Android. English is the
source language; translations live in Tolgee, project **stashy** on https://tolgee.shelf.am
(project id 2, languages de, fr, nl, sv, da, nb, pl, ja, pt-BR, zh-Hans, zh-Hant, ar).

| | Swift | Kotlin |
|---|---|---|
| plain text | `tr("play_count")` | `tr(R.string.play_count)` |
| with values | `tr("arg_scenes", count)` | `tr(R.string.arg_scenes, count)` |
| file | `stashy/Localizable.xcstrings` | `android/app/src/main/res/values*/strings.xml` |

`tr` is defined in `stashy/Localization.swift` and `android/.../stashy/Localization.kt`. Values
are always passed as text (`%@`, `%1$s`), in the order of the placeholders `{0}`, `{1}` in Tolgee.

## Key names

snake_case, named after the English text and its role. One key per text: before adding one,
search `values/strings.xml` for the same text (also in other capitalisation). Never build a text
from pieces (`tr("action_edit") + " " + tr("filter")`): word order and word forms differ between
languages, so "Edit Filter" is its own key.

| Prefix | Role | Example |
|---|---|---|
| — | Stash's own terms keep Stash's key | `scenes`, `o_count`, `play_count` |
| — | labels, titles, menu items | `watch_time`, `now_playing`, `settings_menu` (ends with "…") |
| `action_` | buttons and commands | `action_edit_filter`, `action_edit_menu` ("Edit…") |
| `confirm_` | question of a confirmation | `confirm_delete_scene` ("Delete scene?") |
| `error_` | failure messages | `error_delete_image` ("Failed to delete image") |
| `loading_` | progress text | `loading_scenes` ("Loading scenes…") |
| `empty_` | nothing-there states | `empty_scenes_found` ("No scenes found") |
| `placeholder_` | search field prompts | `placeholder_search_tags` ("Search tags…") |
| `hint_` | sentences: footers, explanations | `hint_drag_to_reorder_cards_below` |

Writing: Title Case for labels, buttons, menus and titles; sentence case for messages and
sentences; "…" (never "..."); no full stop after a short message. Symbols (✓, ▲, ⏭) and all-caps
styling belong in code (`"✓ " + tr("off")`, `tr("o_count").uppercased()`), not in the text.

## Adding or changing a text

1. Add the key with its English text to `android/app/src/main/res/values/strings.xml`.
2. Use it on both platforms (`tr(...)`), also on Android when the feature is iOS-first.
3. `tools/l10n/tolgee.sh push` sends new keys and changed English to Tolgee.
4. Translate in Tolgee, then `tools/l10n/tolgee.sh pull` writes `Localizable.xcstrings` and the
   `values-*/strings.xml` files. Commit them.

Both commands need `TOLGEE_API_KEY` (a project API key of "stashy", Tolgee › Project › Integrate
or Settings › API keys) in the environment. Never commit it.

## Terms

`localization/glossary.csv` (from `glossary.py`) maps the app's wording to Stash's own UI
(stashapp/stash locales), including Stash's translation of each term per target language. Use
Stash's term when one exists. `localization/keys.csv` lists every key with its English text and
how often each platform uses it.

## Scripts

- `glossary.py` — compares the app's wording with Stash; writes `localization/glossary*.{csv,md}`.
- `migrate_literals.py` — the one-time move of hard-coded literals onto keys (kept for reference
  and for files that still hold literals; run with `--samples 40` to see what it would change).
- `tolgee.sh` — push / pull with Tolgee.
