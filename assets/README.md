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
