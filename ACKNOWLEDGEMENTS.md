# Sources and attribution

Florilegium was created by [Kevin Raymond](https://github.com/kevinraymond/florilegium).
The original MIT license is preserved in [LICENSE](LICENSE).

This fork adapts two other MIT-licensed contributions, with their source revisions
pinned here so the origin of the work remains clear:

- [K1o0n, commit 72ebc0f](https://github.com/K1o0n/florilegium/commit/72ebc0f15d635981ff48c9be55b98185f767ba8b):
  botanical digit strokes, broad-nib lettering and the idea of growing the page
  label from the footer stem. These are adapted in `numeral.lua`, `folio.lua` and
  `flora.stem`. This fork adds Roman strokes, upright mirrored lettering,
  reservation-aware placement, size controls and searchable label text.
- [wilsybubs, commit 6f1d846](https://github.com/wilsybubs/florilegium/commit/6f1d8467d747514c9edcf091d785c3ddeda8b7db):
  replaceable drawing sinks, external XeTeX rendering, its item/mark protocol,
  the minimal PDF writer and plain-texlua fontloader bootstrap. These informed
  `ink.lua`, `pdfwriter.lua`, `fontreader.lua` and the XeTeX host and driver.
  The integration here shares layout settings, physical reservations, fallback
  behavior and page labels across engines, with a no-shell-escape build command.
- [wilsybubs, commit 178b8da](https://github.com/wilsybubs/florilegium/commit/178b8dae627c7e6c4002f743157e6388ecc1a00d):
  its discussion of offset-aware mirroring prompted the physical-coordinate
  regression check. This fork fixes the background placement at its origin,
  rather than applying the offset twice in geometry and drawing placement.

Spread/fixed variation, monochrome artwork, the matching divider, the source-kit
workflow, and the additional integration/visual checks were developed in this fork.
No third-party font binaries are bundled.

The platform contract serializer uses David Kolf's **dkjson 2.11**
([author download](https://dkolf.de/dkjson-lua/dkjson-2.11.lua)), vendored
without changes as `pattern_json.lua`. Its MIT copyright and permission notice
is retained in that file. The verified upstream SHA-256 is recorded in
`artifacts/receipts/03/dkjson-dependency.json`. This dependency is independent of
the existing floral code. No LPeg module or automatic native dependency is required.
