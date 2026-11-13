# Original cross-family collections

The Compass Garden collection is an original design. Its recipes and the collection record are separate from source-reproduction fixtures. The default recipe seed is 27. All dimensions are cm.

## Implemented products

| Product | Construction and preconditions | Preserved meaning | Acceptance output |
| --- | --- | --- | --- |
| Coordinated document collection | Two 16 × 20 cm pages use a shared ink/copper palette and explicit scale hierarchy for margin, initial, divider, folio, inline ornament and spread | Each child retains its validated instance and recipe. Initials and folios have upright visible outlines and searchable logical text | `collection.pdf`, `collection-1.svg`, `collection-2.svg` |
| Knot and botanical hybrid | A planar Celtic scaffold has an explicit authored open sector. Its selected port supplies the botanical stem root and direction | Strand traversal, alternating crossings and clearance stay under the Celtic validator. The attached leaf retains its declared port reference | `hybrid.pdf`, `hybrid.svg`, `hybrid.instance` |
| Decorated tiling | A Penrose P3 patch has strictly convex CCW cells. Each shared edge owns one midpoint port and supplies opposite inward tangents of equal physical width | The source tiling's frame, chirality, hierarchy, global vertices and matching decoration remain intact. Compass-star paths are a decoration overlay | `decorated.pdf`, `decorated.svg`, `ports.json` |
| Detail view | A uniformly scaled/cropped view lowers a stored Spectre instance and overlays cell centers and hierarchy relationships | IDs, hierarchy and structural geometry stay unchanged. Dashed parent-child leaders reveal nesting. The companion JSON provides each annotation's cell, prototype and chirality | `detail.pdf`, `detail.svg`, `detail.json` |

The shared nonfloral exemplar is the compass-star decoration. Two spread views crop the same globally framed aperiodic instance at (x=0), with equal scale on the facing pages. Clipping keeps the child clip scopes and each page's physical placement explicit.

## Public Lua workflow

Register `pattern_celtic`, `pattern_penrose` and `pattern_collection_assets` with the normal registry. Generate members through `pattern_recipe.execute`. The five contracts continue to own each member's semantics, view, scene and build record.

`pattern_collection.page(bounds, panels)` places resolved child plans with a positive uniform scale. Each panel has an ID, a plan and slot bounds. Both visible glyph outlines and their logical text receive the same placement. Font resources with a common ID must have identical content. The result uses the shared PDF/SVG serializers.

`decorate(instance, view, definition, scene, color)` returns a validated scene plus a typed port record. Adjacent cells meet at the same globally owned midpoint with opposite inward normals. The curve starts along that normal, making both sides share the tangent line. A third incident cell, an incompatible normal, a nonconvex cell or an undeclared semantic reference fails validation.

`detail(registry, definition, instance, view, style, context)` returns a validated annotated scene and its hierarchy/annotation record. It lowers the supplied instance and checks its structural bytes afterward.

`record(members, products)` stores a small manifest with canonical member recipe/instance filenames and hashes, validation evidence, palette, rendering specifications and page placements. Keep each referenced data file beside the manifest. `replay(bytes, registry, environment, resolve)` uses the supplied data resolver, verifies member integrity, executes the recipes against the supplied actual source environment, requires the same instances, and reconstructs every rendering and page. Member filenames are restricted to their declared safe ID plus the expected suffix. Every data file retains the existing parser limit. A source change that produces different construction data requires an explicit new collection record.

Run `texlua tools/collectioncheck.lua` and `python3 tools/collection_oracle.py`. The harness exports the four products and checks complete collection replay, malformed controls and incompatible compositions. The independent audit verifies the port geometry, source hashes, hierarchy and searchable page labels.

## Compatibility review

Upstream was reviewed on 5 November 2026 at `efee1ffe2e624c0a369e16758e8a52502fa06c05`. Its geometric theme replaces primitive drawing within its garden and adds crystals. Its math theme has a separate page composition with figures and equations. Its intensity control changes the tone ramp and accent lightening. The fork retains the verified legacy composition and opts into the collection mappings below. [Upstream themes](https://github.com/kevinraymond/florilegium/blob/efee1ffe2e624c0a369e16758e8a52502fa06c05/docs/themes.md), [upstream options and inline API](https://github.com/kevinraymond/florilegium/blob/efee1ffe2e624c0a369e16758e8a52502fa06c05/florilegium.sty), [upstream color implementation](https://github.com/kevinraymond/florilegium/blob/efee1ffe2e624c0a369e16758e8a52502fa06c05/florilegium-ink.lua)

| Control | Collection API behavior | Compatibility boundary |
| --- | --- | --- |
| Legacy density | `legacy_geometry(g, {density=...})` copies the host packet and applies the existing `layout.resolve` behavior | `full=1`, `balanced=0.6`, `airy=0.3`, numeric 0.2–1. Values below 0.2 are rejected. Use the result as the legacy adapter's explicit generation input |
| Intensity | `palette` and `controlled_plan` lighten the shared RGB palette toward white over 0–1, preserving path geometry, stroke width and opacity | This is a declared RGB collection mapping. Upstream's OKLCH tone-ramp transformation remains its own behavior |
| Botanical collection theme | `controlled_plan` accepts an existing growth instance or declared knot/botanical hybrid and applies the shared palette | It checks semantic capability before painting |
| Compass collection theme | `controlled_plan(..., {theme="compass"}, ...)` creates the actual matched-port tiling overlay | It requires a supported convex tiling and preserves its validator. This named collection theme has its own semantics |
| Upstream geometric/math themes | Clear unsupported-theme error | Those upstream implementations are absent from this collection API |
| Inline ornaments | `inline(kind,size,seed,angle)` produces a data-only recipe for `leaf`, `flower` or `divider`, size 0.2–2 cm and angle −180°–180° | Fixed integer seeds use the common recipe rules. Unknown motifs are rejected. Font-bearing initial/folio assets use their separate upright recipe path |
| Initial and folio text | Real glyph outlines plus logical/search text through the shared renderer | The supplied font must contain every requested glyph. Width limits and unknown glyphs produce errors |

The collection API has no process-global theme mutation. An intensity edit changes paint. A density edit is an explicit generation input and is rejected when applied to an already generated collection member. Existing legacy density values and baseline paths continue through the existing API.
