# Shared contracts, schema 1

Executable schemas live in `pattern.lua`; registration/context boundaries in
`pattern_registry.lua`. `pattern_examples.lua` supplies three running examples,
checked with `texlua tools/contractcheck.lua` from the repository root. Flat Lua
modules preserve the existing source-kit and `require` conventions. Existing
floral modules and both TeX adapters are unchanged.

## Data and ownership

Every record has `kind`, integer `schema_version=1`, stable string `id` and
optional `extensions`. Constructors validate and copy their input, returning a
recursive read-only snapshot. `plain` makes a mutable owned copy; `snapshot`
freezes arbitrary portable data. Lua extension code is trusted: raw/debug access
is not a security boundary. JSON data excludes null, nonfinite numbers, invalid
UTF-8, unsafe integers, mixed/sparse arrays, cycles and excessive nesting. Use
`array()` for an empty array; an unmarked empty table is an object. No functions
or process resources enter a durable record.

The Design Specification remains the validated planner input, separate from the
five durable contracts. It names a definition/version, typed parameters, inputs,
constraints, style, seed and document context. Undeclared controls fail. Numeric
ranges and required values are enforced; explicit domain-specific input and
constraint checks belong to each generator. The planner is implemented in 07.

| Contract | Required content and invariants |
| --- | --- |
| Definition | family/version, capability tags, parameter declarations, explicit units, transform policy and assumptions |
| Instance | matching definition reference, fixed right-handed 2D/3D construction frame, semantic structures and generator provenance |
| View | instance reference, affine placement, crop, protected-content regions, document units and explicit validity scope; 3D projection includes a 4×4 matrix and visibility policy |
| Scene | instance/view references, semantic operation references, exact view clip metadata, paint and actual resource bytes; empty lowering fails |
| Build record | source revision, runtime/version, seed, dependencies, inputs, lineage, validation, outputs, diagnostics and budgets; complete requires nonempty checks and output evidence |

Definition units are `cm`, `mm`, `bp` or abstract `unit`. The construction frame
retains that unit; document views and scene coordinates use cm, right-handed
mathematical axes. Affine order is `[a,b,c,d,tx,ty]`, mapping `(x,y)` to
`(a*x+c*y+tx,b*x+d*y+ty)`. A lowerer must explicitly apply the unit conversion;
the three examples use cm. A symbol resource additionally declares its own cm
or bp coordinates. Adapter-specific page-axis conversion belongs at rendering.
Bounds are `[xmin,ymin,xmax,ymax]`, strictly positive. The schema's affine
degeneracy/orthogonality tolerance is 1e-9; scale-aware geometry is stage 05.

Metric-constrained definitions reject nonuniform scale/shear. Reflections and
uniform scale obey the declared policy. A projection or deliberate distortion
must be a separate derived view labelled `visualization_only`; it cannot alter
the stored instance or claim preserved construction metrics. A crop never
regenerates the patch. Protected regions retain the role `protected_content`.

## Semantic structures

Only a definition's declared tags are present; no universal mandatory geometry
object is imposed. IDs are globally unique within an instance, assigned from
construction lineage by generators, never rounded drawing coordinates.

| Tag | Retained semantics |
| --- | --- |
| graph | dimensioned vertices, edge endpoint references, incidence; self-loops require an explicit future representation |
| strands | components, endpoint ports, closure, optional alternation policy, ordered crossing encounters, over/under roles, explicit self-crossing |
| tiling | vertices, shared edges with incident owner and boundary role, oriented cell boundaries, prototype and signed chirality, optional parent/child history |
| growth | nodes, points, parent references and declared roots; cycles rejected |
| field | explicit sample representation, domain bounds, vector and nonnegative density samples |
| text | UTF-8 runs, explicit direction, complete unique reading order; glyph shaping is a later stage |
| curve3d | 3D vertices and curve endpoint connectivity, separate projected view |

Interior tiling edges have exactly two distinct incident cells with opposite
boundary directions; patch boundaries have one. Owners must be incident.
Declared histories have single parents and no cycles. Schema checks establish
representation integrity, not source-family geometric theorems: each generator
must independently validate construction-specific closure, metric or matching
rules. The tiny tiling validator checks analytic square areas and edge closure.

Graph/strand tags accommodate Celtic topology; tiling accommodates Islamic,
Penrose and Spectre constructions; growth accommodates floral output. These are
representation claims for the five early demonstrations, not completed family
algorithms. Synthetic text, strand, field and 3D tests only verify contracts.

## Registration, failures and extension boundaries

A registry stores an owned immutable definition and `generate(spec,context)`,
`validate(instance,context)`, `lower(instance,view,style,context)` callbacks.
Nonempty inputs/constraints require a `validate_inputs` callback returning true.
Generation returns an instance only after structural and generator validation;
empty validation reports fail. Lowering accepts a validated view and independent
style; operations retain semantic references. Unknown example style controls
fail. General style declarations and full renderers belong to later stages.

Contexts carry explicit seed, source, version and frame metadata. Named-stream
requests require a configured provider; there is no global random fallback.
Portable domain derivation and versioned vectors are implemented by stage04; see RECIPES.md. Callbacks charge
named object/operation/byte budgets at bounded work intervals; cancellation and
budget exhaustion return distinct failure diagnostics, never accepted instances.
The registry also charges serialized scene bytes and drawing operations.
This is cooperative cancellation for trusted generators; untrusted workers need
host limits. Validation exceptions and failed outcomes remain visible.

Repairs are explicit functions from an existing immutable instance to a new
validated instance. Their Build record lineage must identify the input digest,
operation/version, parameters, reason, changed semantic IDs and validation before
and after. A repaired instance must pass the same applicable validator. Crop,
mask and paint changes are views/styles and cannot be recorded as topology repair.
No generic repair algorithm is implemented here.

An offline solver exchanges the same serialized instance, never renderer-only
paths. Its Build record must bind exact input/constraint digests, solver/version,
configuration, seed, result digest, numerical assumptions and replay validation.
Import must revalidate the instance and the owning family invariants. Solver
execution/replay is implemented only at its owning stage; no solver fallback is
enabled by this interface.

The scene vocabulary starts with M/L/C/Z paths, RGB fill/stroke, positive stroke
width, opacity, normal/multiply compositing, symbol resources and semantic text
placement. Clip metadata is mandatory, but rendering it is stage 06. The floral
example captures actual existing flower PDF drawing commands and graphics
states as a generic bp symbol resource with an explicit PDF-only variant. It is
an interoperability proof, not an SVG renderer or floral migration. It runs in
the check's isolated process and configures the legacy module for that fixture.
Stage 06 supplies scene backends, 08 migrates full floral semantics; no core
branch tests a family name.

## Serialization and migration

Object keys sort bytewise, array order is semantic, finite numbers use 17-digit
round-trip spelling and zero has one spelling. The serializer is deterministic
for the supported profile; stage04 supplies numeric/hash vectors on Lua5.3/5.4.
dkjson 2.11 provides UTF-8 quoting and decoding, with its full upstream MIT notice.
`deserialize` reconstructs a specified validated contract, rejects trailing data
and applies a 2 MiB input limit. Stage04 now supplies strict recipe parsing,
duplicate-key rejection and domain hashes; see RECIPES.md. This entry point
also uses the strict parser.
Unsupported versions fail explicitly. Future migrations must name source/target
versions, preserve their original input receipt and run target validation; no
silent inference from missing fields or unknown future tags.

## Browser runtime decision gate (31)

Evaluate embedded Lua candidates using identical modules, fixtures and seeds:
Lua 5.3 integer/bit-operation semantics required by existing floral PRNG;
floating-point and canonical numeric behavior; UTF-8 and table iteration rules;
golden PRNG and semantic digests; PDF/SVG export parity; cancellation/worker
support; no native process/filesystem assumptions; maintained license and supply
chain; compressed dependency/download size, startup cost and memory. Measure
these rather than selecting by API familiarity. A JavaScript port of geometry
is excluded. Lupa 2.8/Lua 5.3 on this Windows host is a development-only check
runner, not the selected browser runtime or a substitute for TeX CI. Browser
parity stays unverified until the same implementations actually run there.

Stage05 extends spatial semantic records with mutually exclusive numeric point or validated rational exact coordinates. See GEOMETRY.md for the bounded coordinate profile, explicit rendering conversion and supported geometry operations. Empty arrays require array(); sparse arrays and executable/unknown data metatable fields fail. No new universal geometry object replaces capability semantics.
