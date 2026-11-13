# The Pattern Atlas

The atlas shows original canonical examples and separate presentation versions for all 22 public profiles. Both versions come from this implementation. The presentation changes paint through the registered Lua renderer and keeps the validated geometry and physical view. The atlas also includes the Compass Garden book, an aperiodic spread, a knot with a botanical attachment, searchable micrography, an exemplar brush and a projected Gothic curve network.

Open `index.html` from the `build/pattern-atlas` folder of the matching CI PDF artifact. The folder is self-contained. Its `gallery.json` maps every output to the recipe, source hashes and validation evidence. `SHA256SUMS` lists every included file. The profile links provide PDF, SVG, recipe and build record. For a full replay, keep the profile's entire `canonical` or `polished` folder.

To build the atlas locally, install Python 3.11+, TeX Live's `texlua` and the Poppler command-line tools. From the source folder:

```sh
python3 tools/export_review.py
texlua tools/collectioncheck.lua
python3 tools/collection_oracle.py
python3 tools/make-gallery.py
python3 tools/check-gallery.py build/pattern-atlas
```

Use a fresh output directory for each build. The [canonical catalog](../examples/cli/catalog.json) pins the method recipes. The [presentation catalog](../examples/gallery/profiles.json) names the separate styles, coverage rows and source-method notes. The [coverage ledger](research/COVERAGE.csv) links each capability to its independent evidence. A tile patch, partial packing, cached witness or projected curve network represents the finite example indicated in its caption.

The [collection guide](design/ORIGINAL-COLLECTIONS.md) explains the original facing-page and hybrid designs. The [export review](validation/EXPORT-REVIEW.md) describes separate diagnostic and print-oriented checks, with their limits. The [quickstart](QUICKSTART.md) covers the CLI, both TeX engines and the browser studio.
