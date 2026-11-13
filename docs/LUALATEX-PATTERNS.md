# Common patterns in LuaLaTeX

The opt-in commands below use the registered Lua generators, structural validators, instances, document views, scenes and shared PDF renderer. Existing authored/grown commands keep their established paths.

Declare data recipes in the preamble. Generate the instance and the recipe's original, validated scene once per distinct recipe/source/runtime/renderer/dependency identity. At page output, the adapter places that cached scene through a positive uniform physical view. Original planner selections, internal clips and semantic references survive placement. A page crop does not generate a new tiling or repair topology.

```tex
\usepackage[grown,nomargin,sections]{florilegium}
\florilegiumpatterndeclare{knot}{my-knot.recipe}
\begin{document}
\florilegiumpatternpage[region=outer]{knot}
\florilegiumpatterninline[3cm]{knot}
\florilegiumpatterndivider[4cm]{knot}
\end{document}
```

The recipe selects its family and supported parameters. The public CLI can inspect definitions and validate recipes before TeX is run. Files resolve relative to the build directory or the normal TeX input search path. For an explicit byte dependency, call `\florilegiumpatterninput{NAME}{FILE}` before declaring its recipe. The recipe's dependency hash must match those bytes. Recipes and dependency inputs have a 2 MiB limit.

Asset names start with a letter and contain up to 64 letters, digits, underscores or hyphens. Duplicate names fail. Declaration and dependency commands are preamble-only. Inline width defaults to the source PDF's natural physical width; zero selects that default. Positive widths scale uniformly. The source recipe crop determines the included box, including any intentional whitespace. A divider is an ordinary shared asset placed in a centered paragraph.

`\florilegiumpatternpage[OPTIONS]{NAME}` puts a marker in the current content. Its background artwork appears on the page that actually ships that marker. A marker inside a float travels with the float. Multiple markers on one page paint in their content order.

| Option | Meaning |
| --- | --- |
| `region=outer` | Default; use the outer physical margin selected by the actual TeX odd/even text layout |
| `region=inner` | Use the opposite margin |
| `region=page` | Fit the source view into the media rectangle |
| `region=content` | Fit into the actual text rectangle |
| `region=header` / `footer` | Use space above the running head or below the running footer |
| `padding=3mm` | Default clearance; accepts 0–2 cm |
| `protect-text=true` | Default; mask the actual text rectangle and running-head/footer bands |
| `protect-text=false` | Explicitly allow artwork in those text areas; other reservations still apply |
| `spread=none` | Default single-page placement |
| `spread=left` / `right` | Shared-instance facing-page view, requiring `region=page,padding=0pt` |

The actual shipped index is separate from `\value{page}` and `\thepage`. TeX's current layout determines the physical text rectangle, including `\hoffset`, `\voffset`, binding offsets and odd/even margins. The adapter cancels the custom offsets inherited by the background picture origin when placing the physical PDF. The shared document context uses actual shipped indices. Printed labels and logical counters remain separate receipt fields. An actual even page starts a left/right spread; its right view must occur on the immediately following actual page, use the same named instance and media size, and share one positive scale and world translation. A missing partner is an error. This profile supports left-to-right, zero-gutter facing pages.

Existing `\florilegiumreserve` and `florilegiumprotect` markers become physical view masks. Their established `grown` option requirement remains. An irregular L-shaped reservation can be represented as the union of two rectangles. Masking leaves the source graph, strands and tiling unchanged. With `sections`, heading markers and their levels are captured without adding markers to short titles, TOCs or bookmarks. Put artwork in the body or provide ordinary short titles for headings used by hyperref.

Text resources and reading order remain in the shared PDF, including initials, folios and micrography. The adapter adds positive uniform scale and translation; it does not mirror text. Source recipes' declared minimum stroke/text sizes are checked again after page fitting and inline/divider scaling, using the shared planner's existing physical validator and tolerances. Stroke checks cover explicit stroke paints; filled-feature thickness is not certified. Explicit 3D projections retain their visualization-only validity. The actual text rectangle must remain inside the media. Fully protected, empty, unsupported or sub-tolerance regions fail visibly. The adapter never substitutes a placeholder image after a construction or view failure.

Build the included book without shell escape:

```sh
python3 tools/build.py examples/patterns/book.tex --engine lua --output-dir build/pattern-book
```

It includes two chapter files, a travelling float, an L-shaped callout, a botanical/knot hybrid, searchable shared-font assets, micrography and a continuous Penrose spread. Its logical counter deliberately starts at 42 on actual page 2. Normal auxiliary-file convergence still applies.

Generated files live in the build directory. `florilegium-pattern-HASH.*` files bind recipe, source, instance, view, scene and build-record evidence; existing files with differing bytes are rejected. Identical files can be reused by other assets or documents. `JOB-patterns.json` records actual page geometry, headings, reservations, inline locations, file hashes and generation/view counts. Keep complete declaration files when retaining replay evidence. Legacy botanical captures use the existing chunked instance transport. TeX documents and installed modules remain trusted code; this is a no-shell-escape build workflow.

`texlua tools/check-pattern-tex.lua` checks the engine-neutral adapter. `python3 tools/pattern_tex_consumer.py` compiles the actual book and load-order/failure cases, measures imported PDF Form transforms, checks protected pixels against unmasked controls, inspects searchable text and verifies included-file plus pattern-state convergence. Native QA uses Poppler, Pillow and pypdf; pypdf is a verification dependency, not a production generator dependency.

The common API also has an external XeLaTeX adapter. Use `tools/build.py --engine xe`; its dependency and convergence checks are required to finish the external passes. See [XeLaTeX patterns and build evidence](XELATEX-PATTERNS.md) for the record protocol, diagnostics and verification scope.

Primary host references inspected 2026-11-05: [LaTeX shipout hooks](https://www.latex-project.org/help/documentation/ltshipout-doc.pdf), v1.0r, sections 1.2/1.6; [graphics bundle guide](https://mirrors.ctan.org/macros/latex/required/graphics/grfguide.pdf), 2026-05-17, section 4.4. The independent parser uses [pypdf ContentStream](https://pypdf.readthedocs.io/en/stable/_modules/pypdf/generic/_data_structures.html), inspected at documentation version 6.21.4; the receipt records the installed QA version.
