# Botanical compatibility and the asymmetric garden

The existing authored score, grown layout and watercolor primitives remain
the authority for the legacy artwork. The optional compatibility entrypoint
observes those actual procedures and validates a common growth instance, then
emits the original native drawing through the existing host sink. It does not
replace TeX text, initials, folio accessibility, dividers, headers, animation
records, or host geometry. Animation still uses the original recording API.

Use `python3 tools/build.py book-demo.tex --engine lua --botanical-contracts`
or the same command with `--engine xe` for the observed build. This is opt-in;
the default build path is unchanged. The observed host entrypoint keeps the
validated geometry and surviving path counts; the native PDF sink owns its
paint. A complete portable recording is available explicitly through
`pattern_botanical_legacy.capture(mode, geometry, palette)`. Supply the actual
canonical cm host geometry (see DOCUMENTS.md) and
`ink.palette_snapshot()` when matching a native palette exactly.

Each observed primitive has a stable procedure name and local occurrence ID,
its actual invocation point and surviving paint-path count. Recorded stems
retain their actual sampled centerlines. An attachment is recorded only where
the invocation/start point lies within 1e-9 cm of a previous sampled stem
segment; the parent, segment and parameter are kept for verification. The
procedure/composition dependency is tracked separately. A floating visitor,
offset terminal flower, invisible primitive or rejected reserved element is
not asserted to be attached merely because it was invoked. Counts are
observations of this finite replay, not estimates of maximum possible ink or
claims of universal connectivity. Legacy occupancy, skips and route failures
remain the original growth statistics.

Complete capture owns the original quantized neutral paths and their semantic
references. `encode_bundle(instance)` returns a small strict JSON semantic
manifest and SHA-256 addressed recording blocks. `decode_bundle(manifest,
provider, definition)` checks actual block bytes, counts and attachments.
Each recording block has at most 32 operations and 2 MiB. No shared parser or
contract limit is enlarged. The captured instance has canonical page-space
coordinates. Use an explicit physical view for a right-side reflection,
page translation and reservation masks; do not reapply TeX offsets. `lower`
partitions contiguous same-owner paint into balanced vector resources, preserving
paint order and clips. The shared renderer uses bounded operation blocks for
this larger private plan representation. `pattern_render.operations(plan)`
iterates either representation. The existing small scene plan and serializers
retain their original geometry and format.

The registry adapters consume `extensions.legacy_geometry` and an optional
`extensions.legacy_capture_style` in the Design Specification. This adapter
freezes captured native paint; a different palette is an explicit new capture,
not an inferred recoloring of legacy watercolor paths. Existing composition
settings, reservations, marks, visitor/season streams and folio controls are
consumed by the original algorithms. New standalone botanical recipes can
define their own construction and painting policies.

## Named new recipe: asymmetric garden

`botanical/asymmetric-garden@1` consumes the actual adaptive Document planner
request: one world-space root anchor, a strictly convex CCW 3–16 vertex panel
inside the admitted page region, physical reservations, a seed and density.
The canonical five-sided fixture is built and exported by
`texlua tools/botanicalcheck.lua`. Its saved recipe, instance, scene and
Build Record are actual reproducible outputs.

The independent Wong–Zongker–Salesin adaptation uses a 0.4 cm candidate grid,
serial rules and the largest eligible free radius within 3.5 cm of an existing
growth tip. Radius is measured against the boundary, protected boxes and
previous occupied motif proxies. The uncapped clearance selects the next
candidate; the 0.82 cm cap limits motif size. Equal clearance uses stable
row-major order. The density sets the minimum admissible radius and bounded
placement count, not ink coverage. Failed candidate addresses are excluded for
the remainder of the finite run. Each accepted branch starts at its parent
point and leaves along the recorded parent direction; the new motif's base is
the branch endpoint. Original Florilegium watercolor stems and motifs paint the
result. Motif choice and paint use independent named streams.

Conservative whole-paint envelopes, including curve extrema and stroke padding,
must fit inside the convex region and miss every reservation before acceptance.
This is stronger than clipping a rectangle afterward, but can reject otherwise
feasible visible clipped shapes. The acceptance oracle independently checks
exact orientation, endpoints, tangent directions, occupied proxies and 80-digit
Bezier extrema. It also renders a view without the reservation mask and requires
pixel equality with the protected view. Nonconvex regions, disconnected or
insufficient placement, cancellation and exhausted budgets fail explicitly.
This is a bounded grid/proxy adaptation, not the paper's medial-axis search,
exclusion reactivation, exact figures, or arbitrary-region coverage.

`make check` retains the existing gates and runs the botanical structural and
render checks. `make botanical-engine-check` rebuilds each shipped example in
both TeX engines through both entrypoints and compares actual pixels and
searchable text. Large reproducible renders stay in build artifacts.
