# Asset provenance

## `art/masjid_header.webp` (bundled)

The illuminated masjid scene in the Create Song header.

- **Source:** extracted from the supplied design reference
  (`design/reference/create_song.png`), columns 440–852 and rows 0–300 (412 × 300 px),
  saved at its native resolution (shown at 2x, i.e. 206 × 150 pt).
- **Edits:** (a) the area behind the credits pill was inpainted (the live pill is
  drawn on top of it); (b) the tail of the subtitle's first line, which overlapped
  the art, was inpainted out. Nothing else was altered; the fade into the
  background is done in code.
- **Not the original artwork.** It is a screenshot-resolution raster; the
  original high-resolution art was not available. It will look soft on 3x
  displays. Replace this file with the original at ≥ 1236 × 900 px (same
  composition) for crisp results; no code change is needed except updating
  `_MasjidArtwork` dimensions if the aspect ratio changes.

## Welcome and Home art (bundled), made by `tool/extract_art.py`

All of these are cut from the supplied design references with the script above, which
can be re-run. They are screenshot-resolution rasters, not the original artwork, so
they are soft on 3x displays. Where a reference element is drawn live by the app, the
pixels under it were filled in by diffusion (no repainting or generation):

| File | Source | Size | Edits |
| --- | --- | --- | --- |
| `art/login_hero.webp` | `login.png` rows 0–700 | 852 × 700 | Status bar, the language pill and the app icon (all drawn live) filled in. The gold arch and the mosque are untouched. |
| `art/home_hero.webp` | `home.png`, hero card, columns 430–822 | 392 × 365 | The "Watch Demo" button filled in (the app has no demo video; it draws its own "How it works" control). The fade from the card into the art is done in code. |
| `art/template_hausa.webp`, `template_arabic`, `template_english`, `template_mixed` | `home.png`, Quick Start images | 180 × 117 each | The "Popular" badge on the first filled in (popularity is not something the app knows). |
| `art/cover_1.webp` … `cover_3.webp` | `home.png`, the three Recent Songs cards | ~257 × 190 | The play button, title and menu dots over each picture's darkened lower part filled in (drawn live). **Generic cover art:** the three pictures are cycled over the user's songs by a hash of the song id. A song has no cover of its own, and the app does not claim otherwise. |
| `brand/deenvoice_icon_384.webp` | `brand/deenvoice_icon.png`, cropped to the gold border | 384 × 384 | Scaled down, and the square backdrop's corners made transparent so the rounded icon sits on any background. Used for the Welcome and Home headers. |

## `brand/deenvoice_icon.png` (source only, not bundled)

The app icon, cropped from `design/reference/app_icon.png` and scaled to
1024 × 1024. Used to generate the web icons in `web/icons/` and `web/favicon.png`.
Android and iOS launcher icons have **not** been generated yet.

## `fonts/` (bundled, SIL Open Font License 1.1)

| File | Family | Source |
| --- | --- | --- |
| `PlayfairDisplay.ttf`, `PlayfairDisplay-Italic.ttf` | Playfair Display (variable, `wght`) | google/fonts `ofl/playfairdisplay` |
| `Inter.ttf` | Inter (variable, `opsz`, `wght`) | google/fonts `ofl/inter` |
| `NotoNaskhArabic.ttf` | Noto Naskh Arabic (variable, `wght`) | google/fonts `ofl/notonaskharabic` |

Licences are alongside as `OFL-*.txt`. Noto Naskh Arabic is the fallback for
Arabic text in all styles (shaping and right-to-left were exercised in tests and
in Chromium).

## Test-only images

`test/fixtures/avatars/` holds two avatar crops from the reference, used only by
the visual-comparison fixtures. They are never imported by `lib/`.
