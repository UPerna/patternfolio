# Review PDF and SVG exports

The 22 recipes in [the CLI catalog](../../examples/cli/catalog.json) cover the public generation profiles. Each preserves its original method fixture. The export review adds a monochrome paint treatment, a diagnostic drawing with small pink crosses at sampled path endpoints, and an SVG quarter window through the same scene. These are derived render views. The crosses show positions in the rendered geometry, including projected curves and lowered glyph outlines. Family-specific checks still certify strand crossings, tile boundaries, reading order and admitted finite geometry.

From the repository root, with Python 3.11+, TeX Live's `texlua`, and Poppler (`pdfinfo`, `pdfimages`, `pdftotext`):

```sh
python3 tools/export_review.py
```

The `build/export-review/` directory contains the native batch record and one complete generated bundle per profile. Read `batch.json` for the current attempt path. `pattern.pdf` and `pattern.svg` are the clean pair. `diagnostic.pdf`, `diagnostic.svg`, `monochrome.pdf`, `monochrome.svg` and `crop.svg` are the review views. `export-review.json` binds each variant to its source scene, instance and recipe; `export-integrity.json` records the audited dimensions and hashes. A separate browser check uses Playwright 1.62.1 and its installed Chromium:

```sh
PATTERN_PLAYWRIGHT=/path/to/node_modules/playwright node tools/export_review.cjs build/export-review build/export-review-browser
```

For example, to generate the Celtic fixture and then replay its validated instance in a fresh directory:

```sh
python3 tools/pattern.py generate examples/cli/celtic.recipe --output ../celtic-clean
python3 tools/pattern.py replay --from ../celtic-clean --output ../celtic-replayed
```

You can regenerate the derived views from a complete all-families batch with `texlua tools/export_review.lua /path/to/batch`. The tool reads the existing instances and scenes. It does not regenerate the design. Source generation and replay instructions are in the [CLI guide](../CLI.md). For LuaLaTeX and XeLaTeX placement, see [the LuaLaTeX guide](../LUALATEX-PATTERNS.md) and [the XeLaTeX guide](../XELATEX-PATTERNS.md).

| What was checked | Interpretation |
| --- | --- |
| Canvas and stroke units | SVG has centimeter dimensions and an explicit viewport. PDF page dimensions agree. The examples use the same canvas, trim, crop and bleed bounds, with no extra bleed area. |
| Paths, clipping and alpha | Both serializers consume the same lowered drawing. PDF clip operators and SVG clip references were inspected. The browser checks transparent interiors of protected areas, preserving the alpha mask through monochrome conversion. The review also checks white-background PDF pixels inside those areas. A fully painted tile can legitimately have no clear pixels. |
| Color, line treatment and assets | Monochrome PDF uses gray paint operators; SVG retains the geometry with neutral paint. Positive widths, caps and joins were checked. Reusable vector symbols are resolved through the scene's resources before export. No embedded raster was found in the reviewed vector exports. Input images or sampled brightness fields can guide generation without becoming output bitmaps. |
| Text | Micrography renders glyph shapes and carries an ordered logical text layer. PDF extraction agrees through the color, diagnostic and monochrome treatments. SVG retains embedded OpenType data and logical labels. Outline artwork in other profiles does not imply searchable text. |
| Appearance | Clean and diagnostic exports were reviewed at their stated sizes and enlarged at seams, crossings, lettering, petals and crop edges. Pink marks belong only to the diagnostic. The compact tile fixtures are finite checks. The partial mosaic has deliberate grout and the projected Gothic example shows a curve network. |
| Host compatibility | Native TeX placements and the specific PDF/SVG renderers have their own test receipts. Colored SVG previews are composites of the rendered alpha layer. Office imports, physical printers, color management, imposed bleed and arbitrary PDF viewers are untested. |

Technical references consulted 2026-11-07: [SVG 2, §§8.6, 8.9 and 8.12](https://www.w3.org/TR/SVG2/coords.html) for coordinate mapping and physical units; [SVG 2, §§13.4–13.5](https://www.w3.org/TR/SVG2/painting.html) for fill, stroke, caps and joins; [ISO 32000-2:2020 reference](https://pdfa.org/resource/iso-32000-2/) for PDF graphics, page boundaries and text semantics (the reviewed outputs declare their actual PDF version); [Playwright Browser API](https://playwright.dev/docs/api/class-browser) for isolated headless inspection. The local raster review used Poppler 26.07.0, pypdf 6.10.0 and Edge 156.0.4314.58. Native CI records its own runtime and exact artifacts.
