# Geometry and topology profile 1

Run `texlua tools/geometrycheck.lua` followed by `python3 tools/geometry_oracle.py`.
The analytical/adversarial suite and independent oracle are required CI checks,
in addition to the existing contract, recipe and floral regressions. Legacy
`space.lua` rectangle routing and `ink.lua` drawing/curve helpers remain intact.
New services do not reinterpret old drawing fingerprints.

## Numerical and identity boundaries

`pattern_geometry.policy(unit,construction_scale,relative?,absolute?)` requires
explicit cm/mm/bp/abstract-unit coordinates. Default relative tolerance is 1e-10;
default absolute allowance is zero. Length tolerance is the maximum of that
allowance, relative tolerance times construction scale, and 32 binary64 epsilons
times the largest coordinate/construction magnitude. Scale is fixed by the
construction frame, not a viewport. Diagnostics retain tolerances and units.
Construction scales are admitted in 1e-40..1e40.

`pattern_predicates` uses a floating filter followed by error-free expansions
for the exact orientation **sign of the supplied binary64 coordinates**. This is
not a sign test on ideal real numbers before input rounding. Inputs must be zero
or have magnitude 1e-50..1e50; this conservative domain and the bounded root
subdivision depth keep intermediate arithmetic away from overflow/underflow.
The guarantee relies on radix-two, exactly rounded binary64 operations, without
extended intermediate precision or fused compiler rewrites. Lua5.3/int64/binary64
and Lua5.4 are tested; browser hardware/runtime parity remains stage31.

Exact sign, geometric proximity and semantic identity are different concepts.
IDs remain generator-assigned lineage strings. No proximity query, numerical
tolerance or display coordinate merges vertices, replaces IDs or repairs
connectivity. Low-level affine transforms permit reflections/shears as geometry
operations; a definition/view still separately decides whether they preserve its
construction validity. Composition rejects nonfinite results. Inversion rejects
singularity and conditioning beyond the requested relative policy.

`pattern_exact` supplies reduced rational coordinates with positive denominators
and numerator/denominator components bounded by 2^26. Arithmetic intermediates
also have a checked exact-integer budget; excessive complexity fails. It is not
arbitrary precision or an algebraic-number field. A spatial semantic record may
carry either numeric `point` or `exact={coordinate_type="rational",components=...}`,
never both. Contracts validate exact data without converting it. Rational segment
intersections and topology checks retain exact results. `render_vertex` is an
explicit conversion boundary and returns absolute error bounds; conversion does
not overwrite the instance. Later tiling stages add their required algebraic
representations; none is silently approximated by this rational profile.

## Intersections, regions and clipping

Segment queries distinguish none, endpoint/proper point, collinear overlap,
zero-length degeneracy and unresolved coordinate precision. Exact signs classify
topology; proper intersection coordinates use exact determinant expansions and
carry a numerical bound. Rational queries use rational arithmetic and return
rational intersections, or a complexity error. Near-collinear lines are never
declared coincident merely because a determinant is small.

`region(outer,holes,policy,options?)` validates simple polygon rings. Vertices are
an open dense list; outer winding is counterclockwise, holes clockwise. Rings
must not self-touch, cross, overlap, or touch another ring; holes must be inside
the outer. Nested holes/islands require a separate multipolygon representation.
Redundant collinear extreme corners require explicit removal. There is no silent
orientation reversal or topology repair. Each ring has at most2000 vertices;
pair checks default to100000 (explicitly configurable up to10000000). An optional
construction context is charged for checks. Budget exhaustion is a failure.
`import_region` revalidates serialized data; raw mutable tables are not accepted
as already-validated regions.

Containment reports inside/outside/boundary, including hole-boundary identity.
Segment clipping returns retained intervals plus zero-dimensional contacts, so a
corner touch is not reported as an empty intersection. A near-boundary interval
that cannot meet the chosen policy is explicitly unresolved. Distinct hits that
collapse numerically are unresolved. Valid empty intersections and zero-length
inputs have different outcomes. The clip is a derived query; original edges and
construction IDs remain unchanged. Protected-content masks are not topology
repairs. Polygon Boolean union/difference and arbitrary curve-region splitting
are outside this module's implemented operations; stage06 uses backend vector
clipping while retaining original semantic curves.

## Cubics and conservative ink

`pattern_curves` implements cubic Bézier evaluation, de Casteljau splitting,
control-hull bounds and derivative-extremum bounds. Near-multiple extrema use
the conservative hull with a receipt. Bounds include numerical padding.
Line/cubic queries isolate roots using exact Bernstein coefficient signs and
dyadic subdivision. A sign-variation count of zero excludes interior roots;
one brackets a unique simple root. Exact endpoint/dyadic multiple roots retain
multiplicity and tangency. Isolated roots carry parameter intervals and point
error bounds. Default depth48/node10000 limits are explicit. Constant curves are
degenerate; coincident curves/lines, unresolved repeated-root clusters and finite
segment endpoint ambiguity are not accepted as an empty hit set. Non-dyadic
multiple roots can remain unresolved. No source-method theorem is inferred from
approximate candidate roots. **General cubic/cubic intersection and weighted
rational/NURBS curves are unsupported**, with explicit diagnostics; callers must
use supported queries or a separately validated solver. These limits are not
advertised as a universal curve-intersection engine.

`pattern_bounds.path` reads semantic M/L/C/Z commands, not PDF/SVG bytes. It returns
geometric bounds and a conservative ink envelope. Stroke widths are in the local
declared unit before the supplied affine matrix; matrix row norms bound projected
radius separately on x/y. Butt/round/square caps and round/bevel/miter joins are
covered. Miter limits are finite, default10; renderers must explicitly emit the
same limit/cap/join rules across backends. Empty paths/unions are tagged empty,
not represented by inverted or infinite boxes. Text/glyph and arbitrary symbol
ink need their own verified metrics at their renderer/font gates.

## Semantic inspection and spatial queries

`pattern_spatial` is a bounded AABB sweep index, default10000 objects, maximum
100000. It owns inserted boxes, uses deterministic bytewise ID ties, and returns
candidate IDs. Box overlap is not a proof of primitive intersection. It provides
the first reliable query interface; performance stage34 may change internals
without changing semantics or ties.

`pattern_topology.inspect` validates contracts, duplicate coordinates/endpoint
pairs, planar edge intersections, graph incidence/components, oriented cell
boundary walks, positive cell areas, cell adjacency and shared-edge ownership.
Numeric cell-area uncertainty is reported; exact coordinates retain rational
area. Graphs may explicitly declare crossing/multiedge/coincident-vertex policy;
these exceptions do not legalize corrupt tilings. No coordinate snapping occurs.
Reports list actual checks and observations. `strand` exposes ordered semantic
crossing encounters, closure/alternation and endpoint ports. `ancestors` exposes
construction parent history and detects cycles. Existing 3D contract checks cover
connectivity only; this module makes no3D intersection/projection validity claim.

## Independent evidence and preserved failures

The saved oracle receipt records10000 Python Fraction comparisons, seed504031,
including2414 exact-expansion paths and eight cases where a naive determinant
has the wrong sign. Small counterexamples are committed in geometry-v1.json.
The required Lua suite emits a fresh seeded corpus of2000 orientations,500
segments,64 dyadic-root plus two non-dyadic-root cubics and128 affine stroke bounds per runtime.
Immutable content-addressed reports bind current source bytes; the Python oracle
checks exact input Fractions, exact segment coordinates/error bounds, factored
root counts/multiplicities and70-digit extrema plus rational stroke samples.
Older source reports remain preserved and are not counted as current evidence.

Adversarial cases include holes, narrow corridors, near misses, touching and
coincident edges, degenerate curves, reflected/ill-conditioned transforms,
large/small scales, corrupted incidence/boundary walks, duplicate identities,
crossings, budgets and exact-coordinate serialization. Initial clipping exposed
a Lua multiple-return aggregation error; the square-with-hole fixture guards
its repair. Sparse arrays and executable data metatables are now rejected rather
than allowing geometry to disappear during traversal. Finite corpus results
support this implementation; they are not proofs of arbitrary downstream family
constructions or infinite tilings.
