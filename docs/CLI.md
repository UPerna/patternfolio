# Florilegium command-line workflow

Use Python 3.11 or newer and the `texlua` runtime supplied with TeX Live. The common entrypoint is `python tools/pattern.py`. It reads data-only JSON recipes and uses the same Lua definitions, instances, document views, scenes and build records as the other adapters.

    python tools/pattern.py capabilities
    python tools/pattern.py schema tiling/periodic
    python tools/pattern.py validate examples/cli/periodic.recipe
    python tools/pattern.py generate examples/cli/periodic.recipe --output "../My patterns Ω/periodic"
    python tools/pattern.py validate-instance --from "../My patterns Ω/periodic"
    python tools/pattern.py replay --from "../My patterns Ω/periodic" --output "../My patterns Ω/replayed"
    python tools/pattern.py render --from "../My patterns Ω/periodic" --format svg --output "../My patterns Ω/svg"
    python tools/pattern.py diagnose "../My patterns Ω/periodic/record.json"

The output directory must be new. Quote paths with spaces. Global controls appear before the command. For example, `python tools/pattern.py --timeout 1200 generate ...` gives that item twenty minutes. The default is 600 seconds. `--lua PATH` chooses a trusted runtime executable. Repeated `--lua-arg ARG` values supply explicit runtime arguments.

| Command | Accepted input and result |
| --- | --- |
| `capabilities` | Lists the 22 supported family IDs, commands, formats and contract versions |
| `schema FAMILY` | Returns the registered family definition, actual parameter types/ranges, assumptions and recipe contract fields |
| `validate RECIPE` | Checks the strict recipe grammar, registered definition and family input preconditions |
| `generate RECIPE --output DIR` | Runs the generator and its structural validator, lowers the view and writes PDF and SVG |
| `validate-instance --from DIR` | Checks stored artifact hashes, recipe binding and the family structural validator |
| `replay --from DIR --output NEW` | Restores and validates the stored instance, then lowers and renders it through the shared core |
| `render --from DIR --output NEW` | Uses the saved recipe's view and selected output formats with the validated stored instance |
| `batch MANIFEST --output DIR` | Builds all items, saves individual outcomes and returns a partial-failure exit code when needed |
| `diagnose RECORD` | Validates and reports an existing build record's status, diagnostics, checks, budgets and lineage |

The three stored-data commands also accept `--recipe FILE --instance FILE --record FILE` for separately stored common-contract data. Each input keeps the 2 MiB parser limit. A complete CLI output directory carries the existing legacy botanical block transport when its frozen watercolor recording needs multiple files.

An ordinary generation writes `recipe.json`, `instance.json`, `view.json`, `scene.json`, `record.json`, `pattern.pdf`, `pattern.svg`, `diagnostic.json` and `result.json`. Spatial Gothic instances also have `network.json`. Legacy captures use `instance-format.json` and named, hash-checked blocks. Keep the entire directory for replay.

`result.json` is the completion marker and contains artifact hashes. Replay verifies that marker and every listed artifact before reading the instance. The parent build record must be complete and bind both the recipe and the original instance digest. The family validator checks the restored semantics. The new build record names its parent and the cached instance. Its generator entrypoint is bypassed, including for cached Escherization and other solver results.

Generation, rendering and replay accept repeated `--format pdf` and `--format svg` selectors. Both are the default. Execution limits use `--limit objects=N`, `--limit operations=N` and `--limit bytes=N`. Unspecified limits retain the recipe budget. Named external dependencies use `--input NAME=PATH` and must match the recipe's declared SHA-256. Binary dependency bytes pass through the managed host bridge without text conversion.

Use the checked examples for the CLI-only all-family workflow.

    python tools/pattern.py batch examples/cli/all-families.json --output "../All patterns Ω"
    python tools/pattern.py batch examples/cli/all-families.json --output "../All patterns Ω" --resume

The catalog covers authored and grown botanical pages, the adaptive botanical panel, periodic tilings, Celtic strands, Islamic PIC and freeform patterns, finite substitutions, Penrose, Spectre, Ammann–Beenker, Hat, finite marked-square completion, Gothic tracery, Escherization, mosaic, stroke textures, mazes, micrography, DecoBrush, spatial Gothic curves and collection ornaments. Each family has an actual input recipe and runs through its declared provider. Solver profiles and optional requirements remain in the family definitions and research coverage ledger.

A batch manifest has this form. Filenames are relative to the manifest, with absolute paths also accepted.

    {
      "schema_version": 1,
      "items": [
        {"id": "border", "command": "generate", "recipe": "border.recipe"},
        {"id": "cached", "command": "replay", "bundle": "saved-border"}
      ]
    }

Item IDs use letters, digits, underscores and hyphens, with a maximum length of 64. A manifest has 1–1000 items. An item's optional `inputs` object maps dependency names to filenames. Batch state records content hashes, source/runtime fingerprints, attempts and outcomes. Resume verifies a completed item's artifacts before skipping it. Modified inputs or damaged outputs create a new attempt directory and preserve prior files. A failed item stays visible while other items proceed. A live batch holds an operating-system file lock, which closes when its owner exits.

Output paths are checked for symbolic links and junctions. The CLI reserves a new destination and publishes complete files using a temporary file and a hard link on the same filesystem. A complete result marker is written after all artifacts. Interrupted attempts retain their recorded state and can be retried through batch resume. Existing output directories are protected. `--allow-source-output` explicitly permits a destination inside the source tree. The output filesystem must support hard links.

Process execution uses argument arrays. Recipes are parsed as bounded UTF-8 JSON, with duplicate keys rejected. The installed Lua modules and selected runtime are trusted code. The established TeX build and export wrappers remain their own trusted-code workflows. The native process handling and Windows lock implementation follow the Python APIs. [Process communication and timeouts](https://docs.python.org/3.11/library/subprocess.html#subprocess.Popen.communicate), [filesystem links](https://docs.python.org/3.11/library/os.html#os.link), [Windows file locking](https://docs.python.org/3.11/library/msvcrt.html#msvcrt.locking)

| Exit code | Meaning |
| --- | --- |
| 0 | Requested operation or valid inspection completed |
| 2 | Invalid command arguments, manifest or input-file encoding |
| 3 | Core contract, structural validation or generation failed |
| 4 | Destination, filesystem or batch ownership error |
| 5 | Batch contains unfinished or failed items |
| 70 | Runtime startup or transport failure |
| 124 | Item exceeded its time limit |
| 130 | User interrupted the command |

Successful commands and errors return JSON on stdout. Help is ordinary readable text. `diagnose` reports the stored build's status and returns success when inspection itself is valid.

Run `texlua tools/check-cli-core.lua` for the shared replay invariants. Run `python3 tools/clicheck.py` for the full public consumer suite, including every family, stored-instance replay, exports, physical page sizes, searchable micrography and failure/recovery cases. It writes evidence and exports under `build/cli/`. The native suite requires the symlink and signal cases on Linux.

Recipe files use LF line endings, enforced by `.gitattributes`, so the example catalog's byte hashes also verify in Windows checkouts and source archives.

The native consumer suite uses Poppler's `pdfinfo` and `pdftotext`. Its explicit `--local-pdf-reader` option uses pypdf for local QA when those tools are unavailable. The receipt records the reader used.

Previously saved Escher witnesses retain their exact geometry, hashes and topology. Recomputed normalized turning-function diagnostics use a tolerance of `1e-12 * max(1, abs(value))`, matching the method's numerical policy. This accommodates the measured `5.6e-17` difference between the earlier native and Windows diagnostic arrays. The improving-witness condition and all combinatorial and geometry certificates still run.
