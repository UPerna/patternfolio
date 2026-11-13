# Document planning, profile 1

`pattern_document` validates supporting document context; `pattern_planner`
prepares generation requests and derives views. The five durable contracts are
unchanged. A validated Design Specification remains the planner input. The
document descriptor is explicit input to that pipeline, not another pattern
model or an additional generator. The existing floral engine stays intact;
full-page semantic migration is stage08.

## Physical frames

Document coordinates use cm, positive y upward. Every page/panel names a physical
media size, its lower-left origin in the shared construction frame, page number,
trim bounds, four bleed distances and four physical margins. Four-tuples use
left/bottom/right/top order. Bleed must fit in media. Content derives from trim,
margins, inner binding offset and a y-up content offset. Recto is odd in a
two-sided document; inner binding is left on recto, right on verso. These offsets
move content and content-relative anchors/reservations, not the world tiling.
Native TeX positive voffset is converted by the legacy host, not mistaken for a
positive y-up document displacement.

Reservations explicitly name page or content coordinates; anchors name world,
page or content coordinates. Normalization records physical masks and world
anchors once. Facing spreads identify an even verso and following odd recto,
their media origins and gutter. Independent panels can deliberately view
overlapping world rectangles. The instance and document must name the same
construction frame, unit and origin. This first planner profile admits2D cm
frames; explicit conversion/projection remains available through the underlying
view contract rather than an inferred planner fallback.

Context snapshots are owned and immutable. `document.import` recomputes and
checks derived metadata after JSON deserialization, including any legacy host
snapshot. Forged/stale derived content is rejected. Crops select media, trim,
bleed, content, or an explicit page-local rectangle. The view translates the
existing world construction into page coordinates; the renderer subsequently
normalizes the crop origin into the output rectangle. Paper offsets are never
added a second time to drawing paths.

## Fixed and adaptive construction

Planning profiles bind a definition/version and explicitly declare fixed-frame,
adaptive, or view-only behavior. Density and focal intent can map only to actual
declared numeric generator parameters. They retain the owner's meaning; the
legacy floral density control changes spacing/branches/detail, not ink coverage.
Unsupported intent is a diagnostic, never a reason to choose a different family.

`prepare_specification` returns a request that still requires its specialized
generator and validation. A fixed tiling uses one world request covering the
document union plus halo; page reservations do not enter structural generation.
An adaptive family explicitly declares media, trim, bleed or content as its
permitted generation region. Its request carries that region, masks and anchors to its
generator. The planner does not pretend that an unconsumed request establishes
adaptation or validated structural avoidance. Packing and new source-family
generation retain their owning stages.

`view` never calls a generator or changes the instance. A source digest binds the
plan to exact instance bytes. Changing a crop reuses IDs, topology, edge ownership,
hierarchy and the fixed world frame. A definition-owned conservative tile-diameter
bound is checked against all existing cell envelopes; the requested generation
halo must cover it. Continuation requires the family's validated planar patch,
no true source boundary in the expanded window and a covered window center.
Insufficient or numerically unresolved coverage requests a larger validated
patch in the same frame. A bounding box alone is not a coverage proof.

Full-tile views admit complete cell geometry inside the crop and conservatively
exclude cells intersecting reservations. Clipped-tile views admit conservative
cell candidates and use the exact view masks at painting. Rational coordinates
are compared to binary64 crop bounds with an exact determinant sign, not their
rounded display points. Rendering conversions and their error bounds remain in
the receipt. Full-tile admission concerns cell geometry; physical trim still
clips stroke fringes at the canvas boundary. Use explicit bleed when those
fringes must survive export.

The lowerer filters separate cell/global-edge paints and rejects ambiguous
grouped references. An edge stays owned by its original semantic cell even when
another incident cell is the one selected for display. Cut edges, masked edge
intervals, selection boundaries and true patch boundaries are separate data.
Straight graph edge cuts similarly retain original endpoints. Curved drawing
paths are not inferred from endpoint chords. Strand closure/endpoints stay
semantic: a clipped closed knot is not reported as a newly broken component.

## Constraints and failures

Minimum stroke and text dimensions inspect the actual shared drawing plan,
including resource and affine transforms. The stroke control measures explicit
stroke widths, not arbitrary filled-feature thickness or clipped fragments.
Text size measures the positioned em scale; it is not a new shaping engine.
Missing measurable content, insufficient size, ill-conditioned transforms and
thresholds inside the affine rounding allowance fail explicitly. Axis-aligned
scales use their direct minimum; general scales retain the established inverse
conditioning check and a64*sqrt(binary64 epsilon)*matrix-norm rounding guard.
Finite80-digit Decimal comparisons independently exercise these measurements;
no universal minimum manufactured-feature guarantee is claimed.

The routing capability uses the existing visibility-graph proposal, then checks
whole-segment exclusion clearance and coverage by the permitted rectangle union.
It does not accept a few clear sample points as a containment proof. A blocked
search preserves the original sampled path in failure evidence. Failure to find
a route is not a mathematical nonexistence proof. Budget exhaustion and
cancellation remain distinct outcomes with their actual budget receipts.

## Existing floral controls

`document.from_legacy_host` translates actual integer scaled-point host snapshots
by calling the unchanged `florilegium.geometry` and `layout.resolve`. The resulting
document content reflects real odd/even margins, hoffset/voffset, head/foot
dimensions and the existing side overhang. Binding and offsets already resolved
in TeX dimensions are not applied again. `legacy_page` normalizes physical/content
reservations back into the canonical garden frame, with a separate artwork
reflection. Native text remains upright and botanical labels retain their
existing counter-reflection. The18mm garden-width rejection matches the existing
grown entry point. Temporary host callbacks are restored even after rejection.

The actual unchanged grower demonstrates adaptation before clipping: occupied
grid cells decrease and motif transactions reject reserved geometry. Existing
`route_failures` remain visible. In the reserved fixture one legacy route fails;
the final safety mask protects ink, but that is not certified continuous routing
or a topology repair. An explicitly requested continuous route uses the separate
checked routing result. Full floral attachment/migration evidence belongs to08.

## Entry points and checks

Construct/import the document, declare/import a bound family planning profile,
prepare a Design Specification request, and run its generator/validator as needed.
Call `planner.view(instance,definition,document,page_id,profile,options,context)`,
then `planner.lower(registry,id,instance,definition,plan,style,context)`.
For saved builds use `planner.recipe`: its versioned view extension stores the
validated document/profile/options, and recipe execution recomputes selection
against the actual generated instance. Build records retain planning validation.
Fixed-frame generation keys bind frame/profile and coverage but leave crops and
masks in view keys; adaptive keys additionally bind the actual page/anchors.
The registry requires the prepared generation data and construction context to
agree. A stale physical template or forged generation context fails validation.
Failures return diagnostics instead of accepted geometry. Render the resulting
scene through the existing shared plan. `render.pdf_document(plans)` creates a
real multi-page PDF with the same serializer; per-page SVG remains the vector
page format. All six verified stage06 PDF/SVG byte digests are regression gates.

`texlua tools/plannercheck.lua` produces standalone, full-tile, facing-page and
overlap fixtures plus actual open/reserved floral pages. The unit grid is an
analytic view fixture, not stage09's periodic/wallpaper implementation.
`python3 tools/planner_oracle.py` uses exact Fractions,80-digit Decimal, parsed
SVG, pdfinfo and independent Inkscape/Poppler rasterizations. It checks physical
origins, trim/margins/binding/offsets, two actual PDF pages, shared world geometry
and overlap pixels, all protected ROIs separately, actual host scaled points and
pre-clip floral adaptation. Full old regressions and both TeX hosts remain
required. Large renders stay in build artifacts; receipts bind actual sources
and output bytes.
