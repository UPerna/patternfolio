# Make your first Florilegium pattern

Run the commands from the extracted source folder. Use Python 3.11 or later. The CLI and TeX examples also need TeX Live's `texlua`, LuaLaTeX or XeLaTeX, and the LaTeX packages in the relevant guide. The browser needs a local HTTP server; Python can provide it. No network geometry service is used. The [glossary](GLOSSARY.md) explains the platform's terms.

## Generate and replay

```sh
python3 tools/pattern.py capabilities
python3 tools/pattern.py generate examples/cli/celtic.recipe --output "../My patterns/Celtic"
python3 tools/pattern.py replay --from "../My patterns/Celtic" --output "../My patterns/Celtic replay"
```

Open `pattern.pdf` or `pattern.svg` in the first output folder. A **recipe** stores the family, parameters, input data, seed and view. An **instance** stores the resulting geometry and its relationships. Keep the whole output folder so **replay** can validate and use that instance directly. Both output folders must be new. On Windows, use the installed `python` command if `python3` is unavailable.

The [CLI guide](CLI.md) describes all commands and error codes. The [export review](validation/EXPORT-REVIEW.md) shows how to produce monochrome, diagnostic and cropped views for every recipe.

## Place patterns in a book

```sh
python3 tools/build.py examples/patterns/book.tex --engine lua --output-dir "build/Lua book"
python3 tools/build.py examples/patterns/book.tex --engine xe --output-dir "build/Xe book"
```

Open `book.pdf` in each output folder. The [LuaLaTeX guide](LUALATEX-PATTERNS.md) explains placement, reserved areas and inline ornaments. The [XeLaTeX guide](XELATEX-PATTERNS.md) explains how the driver prepares the same vector assets between compiler passes. Use the driver for the full book so the page locations and pattern requests can settle across passes.

## Use the browser studio

```sh
python3 tools/webpackage.py
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8000/`. Choose a starting recipe, then select **Generate structure**. Export PDF, SVG or the recipe. Use **Save Workspace** to keep the applied result and unfinished edits together. The [studio guide](browser-editor.md) covers imports, cropping, edit timing and backup.

## Change a result

Seed, construction parameters, guides and exemplars can change the instance; generate again to apply them. Paint and supported crop changes can reuse the validated instance. A **protected region** is a rectangle reserved for other content. Changing one may affect either generation or the view, depending on the family and the planner. The editor explains when it needs a new generation. Keep the original recipe and save a separately named copy for a new design.

## If a command fails

| Symptom | What to check |
| --- | --- |
| `texlua` is missing | Put the TeX Live binaries on the command path or select the installed executable with the CLI's `--lua` option. |
| Output already exists | Choose a new directory. Keep the old directory as a replayable result. |
| Stored output checksum fails | Restore the complete original bundle, including any legacy blocks or spatial network file. Use a recipe to regenerate if the instance is unavailable. |
| Preview still shows the previous design | Apply the edits, then generate if the editor says the structure changed. Export becomes available when the new result passes validation. |
| Browser assets fail to load | Build the browser files again and serve `build/web` over HTTP. Keep the same origin to retain browser storage, or restore a saved workspace. |
| The optimizer is absent | Use the bundled verified witness for the ordinary Escherization recipe. Installing a new optional solver is a separate workflow. |

For exact reproduction, keep the recipe, output bundle and tested source revision. Native and browser receipts state which comparisons are byte exact and which admit binary64 rounding differences. Review the [source and fidelity notes](research/SOURCES.md) before interpreting a finite example as a broader mathematical result.
