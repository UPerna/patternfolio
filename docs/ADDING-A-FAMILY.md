# Add a pattern family

Start with the [five contracts](architecture/CONTRACTS.md) and the running examples in `pattern_examples.lua`. A **family** is a registered construction with stated inputs, assumptions and validation rules. It can share output tools with other families while keeping its own algorithm and semantic data.

1. Give the definition a stable ID and version. Declare typed parameters, supported semantic structures, units, valid transformations and assumptions. Validate family-specific inputs before running the algorithm. Use the [document planner](architecture/DOCUMENTS.md) when the design depends on page constraints.
2. Register a single Lua implementation with `pattern_registry.new():register(definition, implementation)`. Supply `generate`, `validate` and `lower`; add `validate_inputs` when you accept input or constraint fields. The construction context tracks work limits, cancellation, verified input bytes and random streams named by their semantic purpose. Keep the construction frame stable when style or crop changes.
3. Return a Pattern Instance with the structure your method actually uses. Examples include an edge graph, a strand crossing assignment, a set of tiles with stable identities, a sampled field, logical text order or 3D curves. Keep relationships explicit until rendering. The structural validator must name meaningful checks and reject a broken instance with a useful diagnostic.
4. Lower a validated instance and its Document View to a Drawable Scene. Reuse the common path, paint, clip, font and symbol records. Scene operations refer to existing semantic IDs. A renderer consumes the same scene plan for PDF and SVG. Keep 3D projection and non-metric visual transformations explicit.
5. Add an original canonical recipe, a separately named presentation example, and a Build Record with source, inputs, validation, resources and output hashes. The [recipe reference](architecture/RECIPES.md) describes deterministic replay and cache identity. Register the family for the public workflow and add its exact recipe hash to the [catalog](../examples/cli/catalog.json); the browser consumes the same Lua module and verified data.
6. Test valid inputs, rejected inputs, repeatability and an independently calculated structural property. Include corruption that the property test must catch. Test style and overlapping crops against the same instance, PDF/SVG physical units and protected regions, then run native and browser parity. Preserve existing fixtures and record comparison tolerances before inspecting results.

## Scope and attribution

Link the actual primary paper or documentation version and relevant sections. Document which method steps are implemented, which are adapted, and what the finite evidence establishes. A finite no-overlap test does not prove a tiling theorem. A screenshot does not certify graph connectivity or logical reading order. A licensed paper does not grant a license to its code, fonts or figure assets.

Use original or properly licensed input data and keep code and data notices separate. Record the capability, owning stage, canonical fixture and evidence in [COVERAGE.csv](research/COVERAGE.csv). The [source notes](research/SOURCES.md) explain the project's vocabulary for source fidelity and optional extensions.

## Local checks

```sh
texlua tools/contractcheck.lua
texlua tools/replaycheck.lua
python3 tools/determinism_oracle.py
python3 tools/clicheck.py
python3 tools/export_review.py
```

Start with the smallest source-specific witness and the independent property test. The full CLI suite checks all public profiles and requires Poppler on Linux for the native reader path. Both TeX adapters and the real browser also have independent gates. Keep local development checks and native CI evidence clearly identified.
