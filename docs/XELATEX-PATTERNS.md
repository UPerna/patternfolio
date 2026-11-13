# Common patterns with XeLaTeX

The recipe, inline, divider and page commands described in [LUALATEX-PATTERNS.md](LUALATEX-PATTERNS.md) use the same `pattern_tex` adapter, semantic generators, validators and PDF renderer in both engines. XeLaTeX records requests and physical positions; `texlua` constructs the assets between compiler passes. It does not run another implementation of the geometry.

```sh
python3 tools/build.py examples/patterns/book.tex --engine xe --output-dir "build/Xe book"
python3 tools/build.py examples/patterns/book.tex --engine lua --output-dir "build/Lua book"
```

The driver always disables shell escape and passes filenames as arguments. Source names may contain spaces and Unicode. Names containing TeX syntax that cannot be passed literally are rejected; job names have a restricted, explicit alphabet. A single build owns its job name and output folder. Use distinct output folders for simultaneous builds.

The new commands remain opt-in. Existing botanical commands retain their host paths, seeds, protected content, layout and fallback policy. Common fonts are recipe resources or explicit dependency bindings; unsupported fonts and impossible physical print minima remain errors. Existing decorated initials retain their declared plain fallback and explicit font diagnostics. Text in shared initial, folio and micrography PDFs stays searchable and upright when included.

## External records and retained identity

The existing `JOB.flo` stream now accepts a version 1 common-pattern protocol:

| Record | Content |
| --- | --- |
| `PHEADER` | Protocol/adapter and actual XeTeX version |
| `PINPUT` / `PDECLARE` | Ordered dependency bindings and named recipe references |
| `PINLINE` | Stable usage index, asset name and physical width in scaled points |
| `PPAGE` | Actual shipped index, separate logical counter/label, page dimensions and TeX offsets |
| `PMARK` | Physical position, heading/protection/inline/view payload and actual shipped index |
| `PEND` | Actual page and inline counts, activation and incomplete-pass flags |

These are trusted TeX-generated records, like the established botanical records. Recipes remain bounded data. The adapter requires the declared protocol and complete records, rejects invalid counts and missing pages, and retains the old botanical-only record profile. Physical marks travel with floats and disappear with discarded pages. Reservations become view masks rather than topology repairs. The actual shipped counter, logical parity for TeX's text layout, printed label and shared spread context remain distinct.

The external host reads the actual recipe/dependency bytes and persists canonical recipes, semantic instances, original scenes, physical views, build records and PDFs using the same contracts as LuaLaTeX. `JOB-patterns.json` retains those references and hashes together with measured document geometry. Identical declarations share a generation. `JOB-patterns.tex` includes the resulting PDF assets at the recorded physical positions, cancelling custom offsets inherited by the background picture.

The record stream alone is not an archival copy of the input files. Retain it with the canonical generated recipe/instance/view/scene files, dependency bytes, source revision and build evidence. Botanical instance bundles retain their existing chunked transport.

## Complete builds and stale data

A cold first pass can contain explicitly reported missing assets and layout estimates. Running the compiler once is not a completed external build. The driver suppresses stale asset metadata, renders the recorded requests, then compiles again until both artwork and document state converge. A compiler success status or an older PDF cannot satisfy this condition.

`JOB-external.json` binds the actual `.flo` bytes, root renderer/adapter sources, recipe and bound dependency bytes, generated outputs, resolved legacy initial fonts and loaded font-reader sources. The Python driver adds compiler/runtime identities, its own byte hash and recorded compiler inputs. It checks those files again before accepting reuse. Renderer, font, recipe, resolution or generated scene/PDF changes invalidate the prior result. Existing generated files with unexpected bytes are preserved and rejected; use a fresh output folder after diagnosing a damaged common cache. Previous generated metadata is retained under its content hash where Windows replacement requires a fallback.

`JOB-build.json` records the exact command and exit status, pass/render log hashes, fresh PDF hash, auxiliary hashes, compiler inputs, stale reasons and acceptance or failure for every attempted pass. It tracks both recorder input and output auxiliaries, including included chapters, `.toc`, `.lof`, `.lot` and hyperlink state. A changing chapter file cannot be hidden by a stable main auxiliary file. The pattern trace participates in convergence too.

The default bound is six passes. `--max-passes` accepts 1–12; a one-pass bound cannot establish convergence. A bounded failure names the changing state and keeps its pass evidence. The lightweight PDF guard checks fresh output and its header/EOF; independent parsing, text, vector and raster checks belong to the native acceptance suite.

## Verification

```sh
texlua tools/check-pattern-xetex.lua
python3 tools/build_statecheck.py
python3 tools/pattern_dual_tex_consumer.py
```

The first command exercises the actual external record adapter and publication behavior without claiming a TeX compilation. The second fault-injects the actual build driver with a synthetic compiler. The third requires real LuaLaTeX, XeLaTeX, `texlua`, Kpathsea, Poppler, Pillow and pypdf. Verification dependencies are separate from production pattern generation.

The native suite builds the included-chapter book and load-order/failure cases in both engines. It independently measures all imported asset positions, full promised text and protected ink. It compares semantic instance identity, source scenes and physical vector operations with a two-scaled-point coordinate bound, then checks colored ornament ink in the actual book pages. Per-component coverage and ink bounds supplement the changed-pixel bound so a low page mean cannot conceal a missing glyph. Shared inline font/PDF bytes compare exactly. Native black body-font rasterization is isolated from ornament raster comparisons; the complete extracted letter sequence is checked separately.

Inline paint is compared in the measured inclusion frame: the inverse positive uniform Form transform is applied to the actual book page, then the page is cropped to the source asset canvas. This keeps actual page clipping and foreground obstruction in the raster; it does not substitute the standalone asset. Physical position is still measured independently against the unchanged 0.01 cm limit. Rotation, reflection and nonuniform scaling are rejected before registration. The unchanged raster limits are 0.005 changed colored pixels, one pixel of ink-bound variation, and per-component coverage. Registration avoids serializer rounding differences moving antialias edges onto different raster grids. See the [pypdf transformation and page-box API](https://pypdf.readthedocs.io/en/stable/user/cropping-and-transforming.html) (6.21.4 documentation, retrieved 6 November 2026, content-only scaling and explicit boxes).

Real compiler fixtures exercise all requested auxiliary files, child-only churn with a stable main aux, first-pass rejection, no-output compiles seeded with old PDFs, actual recipe/font/renderer changes, damaged scene preservation and visible searchable font fallback. Earlier legacy document, outline, offset, export and packaging checks remain in CI. The stage checkpoint records which exact revisions and native environments have actually passed; merely adding the suite is not acceptance.

Hosted editors have not been tested. A hosted XeLaTeX editor must support the external render-and-recompile process or receive matching prebuilt assets; a lone compiler pass is insufficient. Native Windows TeX is also untested; local Windows Lua tests cover record handling, paths and metadata replacement, not a Windows TeX distribution.

Primary interfaces inspected 2026-11-06: [XeTeX reference, 2025-02-11](https://ctan.math.illinois.edu/info/xetexref/xetex-reference.pdf), §§8.1/8.5; [LaTeX shipout, v1.0r](https://raw.githubusercontent.com/latex3/latex2e/develop/base/ltshipout.dtx), counters/background; [LaTeX file handling, v1.2w](https://raw.githubusercontent.com/latex3/latex2e/develop/base/ltfiles.dtx), `include`; [Web2c 2026](https://tug.org/texinfohtml/web2c.html), recorder; [Kpathsea 6.4.2/dev](https://tug.org/texinfohtml/kpathsea.html), format lookup; [pypdf visitors](https://pypdf.readthedocs.io/en/stable/user/extract-text.html), documentation 6.21.4. Actual installed verification versions are recorded by the suite.

Independent PDF QA preserves original text-show byte strings. Font CIDs are not Unicode strings; hidden-text filtering retains their original bytes before decoding. Inline raster registration wraps the original page-content bytes, verifies the written stream exactly, and retains the original page crop as an explicit clip. Local actual-page controls reject stream clipping, foreground occlusion and implicit page-edge cropping; a deliberately hidden actual CID initial also fails visibility verification.
