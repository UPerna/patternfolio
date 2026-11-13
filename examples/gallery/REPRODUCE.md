# Reproduce the Pattern Atlas

Open `index.html` in a browser, or serve this folder with `python3 -m http.server --bind 127.0.0.1`. Keep the folder structure intact. `gallery.json` maps every example to the canonical recipe, display recipe, source bytes, validation and outputs. `SHA256SUMS` identifies the exact artifact files. The `notices` folder contains the source bibliography, coverage ledger and code/font notices.

The canonical and presentation views come from the same verified instance. The canonical example retains the original fixture. The presentation recipe changes native paint through the supported style API. The display page scales images for reading; the PDF and SVG downloads retain the recipe's physical dimensions. Examples are finite, and a rendered view does not establish a general mathematical guarantee.

From the matching Florilegium source folder, with the atlas unzipped beside it:

```sh
python3 tools/pattern.py replay --from ../pattern-atlas/profiles/celtic/canonical --output "../Celtic canonical replay"
python3 tools/pattern.py replay --from ../pattern-atlas/profiles/celtic/polished --output "../Celtic presentation replay"
python3 tools/pattern.py generate ../pattern-atlas/profiles/celtic/source.recipe --output "../Celtic regenerated"
```

Use the complete bundle directory; it may contain legacy blocks or a separate 3D network. With the matching runtime and source, replay preserves the validated instance and vector bytes. Across tested hosts, consult the comparison policy in the source package. Logical identity and numerical equality within the documented tolerance can apply even when floating point spelling differs.

To build the whole atlas from the matching source, install Python 3.11+, TeX Live's `texlua` and Poppler tools. Run these commands in the source folder:

```sh
python3 tools/export_review.py
texlua tools/collectioncheck.lua
python3 tools/collection_oracle.py
python3 tools/make-gallery.py
python3 tools/check-gallery.py build/pattern-atlas
```

Use a fresh `build/pattern-atlas` output or name a new directory with `--output`. The Compass Garden collection includes both facing pages, a hybrid Celtic and botanical example, and decorated tiling. The [collection record](collection/original-collection.json) gives the member hashes and placement. The [collection receipt](collection/receipt.json) and [independent checks](collection/oracle.json) give its validation evidence.
