# Compatibility, comparisons and licenses

| Workflow | Verified scope | Practical limit |
| --- | --- | --- |
| CLI | All 22 public profiles generate, validate, replay and export on the native TeX Live `texlua` path. The exact-revision suite includes space and Unicode paths, bounded failures, and an extracted source kit. | Keep the complete output folder. The separate Windows Lupa functional host needs an ASCII source path; space-containing source paths and Unicode output paths were exercised. Native Windows TeX is untested. |
| LuaLaTeX and XeLaTeX | The native Linux jobs compile the common example book with both adapters. They verify page placement, searchable text, protected regions and admitted inline limits. | XeLaTeX uses the supplied build driver and `texlua` between passes. Other operating-system installations are not certified. |
| Local browser | The shared Lua runtime, editor and exports are exercised in real Chromium on Linux, with separate Windows Edge functional checks. The source kit builds the same browser assets. | Use a local HTTP server. Safari, Firefox, mobile devices and other OS/browser combinations remain untested. A loaded editor can continue offline; a fresh load still needs its local assets. |
| PDF and SVG | The shared scene supplies vectors with physical units, crop, masks and explicit paint. The reviewed text profile has logical reading order in addition to outlines. | Office imports, production printing, arbitrary PDF viewers and color-managed print workflows are untested. |
| Solvers and spatial models | Verified Escher witnesses replay without an optimizer. Spatial Gothic retains an explicit 3D curve network and exported views. | Fresh optional solver runs require their declared versioned dependencies. Projected views and network JSON do not supply manufacturing meshes. |

For the same supported runtime and source, retained-instance replay checks exact instance, scene and PDF/SVG bytes. The native and browser comparison reports distinguish exact pairs from the named Micrography and DecoBrush binary64 comparisons. They check structure and reading order independently and reject injected differences. The Windows functional export review separately records three numeric-only differences relative to native TeX. Neither host difference relaxes any source-specific structural test. See [the accepted export evidence](../artifacts/receipts/35/acceptance.json), [browser runtime policy](architecture/BROWSER-RUNTIME.md) and [the CLI guide](CLI.md).

| Material | License or source notice |
| --- | --- |
| Florilegium code and independently authored examples | [MIT](../LICENSE). The method bibliography does not grant rights to third-party artwork or code. |
| Hat substitution tables | [HatViz BSD 3-Clause notice](research/licenses/HATVIZ-BSD-3-Clause.txt), with pinned source and scope in [the Hat design note](architecture/HAT_AND_BOUNDED.md). |
| JSON and browser components | dkjson 2.11 MIT notice in [its source](../pattern_json.lua); [Wasmoon MIT](../web/vendor/wasmoon-1.16.0/LICENSE), [Lua notice](../web/vendor/wasmoon-1.16.0/LUA-LICENSE.txt), and [hash-wasm MIT](../web/vendor/hash-wasm-4.12.0/LICENSE) and [SHA-256 C notice](../web/vendor/hash-wasm-4.12.0/SHA256-C-LICENSE.txt). |
| Font data and derivative outlines | [Pattern Micrography](fonts/README-PatternMicrography.md) and [Pattern Scene Fixture](fonts/README-PatternSceneFixture.md) retain [GUST Font License](fonts/GUST-FONT-LICENSE.md) and [LPPL 1.3c](fonts/LPPL-1.3c.md) notices. |
| Reference papers and demonstrations | [Sources and fidelity boundaries](research/SOURCES.md), [versioned bibliography](research/BIBLIOGRAPHY.json). Independently authored fixtures are kept separate from reference material. |
