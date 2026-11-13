# Data recipes for the public CLI

`catalog.json` records one supported recipe for each public family and its source hash. `all-families.json` is a batch manifest for those 22 recipes.

From the source root, run `python tools/pattern.py batch examples/cli/all-families.json --output "../All patterns"`. Inspect each attempt's `result.json` and `record.json`. The full workflow and command reference are in [CLI.md](../../docs/CLI.md).

These consumer examples reuse accepted family fixtures. The Hat and legacy botanical examples spell out the supported inputs from their existing native harnesses. The Compass Garden original designs remain in the separate collection examples directory. Font and code notices stay with the source package.
