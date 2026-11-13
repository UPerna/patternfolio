# Shared vector scenes, profile 1

Stage06 uses the same Lua scene, resource resolver and immutable drawing plan for
native PDF and SVG. No raster substitution is supported. `pattern_render.plan`
revalidates the scene against its instance, view and definition before resolving
resources; serializers accept that plan. Generators emit neutral operations.
Topology, ownership and text runs stay in the instance. Every visible path retains
its semantic source, including paths expanded from symbols and glyphs.

Document coordinates are centimeters, positive y upward. A crop defines the exact
physical output rectangle: SVG width/height are cm, PDF MediaBox is cm*72/2.54 bp.
SVG reverses y once at the root; PDF uses an explicit cm-to-bp matrix. Path-local
affine transforms remain attached to strokes, so nonuniformly transformed strokes
are ellipses rather than an incorrectly rescaled uniform line width. Resource
transforms map the resource's declared cm/bp coordinates into document cm.

Paths support M/L/C/Z, compound subpaths, nonzero/evenodd fill, gray/RGB colors,
positive physical stroke widths, butt/round/square caps, miter/round/bevel joins,
explicit miter limit (default10), dashes, opacity and normal/multiply blending.
Fill precedes stroke as two ordered paints; opacity applies to each paint. There
are no implicit isolated groups, filters, gradients or other blend modes. PDF
numbers expand exponent notation into valid decimal tokens. SVG dash offset and
PDF dash phase share the positive pattern-advance convention. Hairlines fail.

Clip pushes are transformed into world coordinates and intersect the current
clip; balanced pops restore it. The root crop is always enforced. Each protected
rectangle intersects a separate evenodd complement, so overlapping reservations
remove their union. A combined evenodd list would incorrectly reopen overlaps.
View masks do not repair instance topology or establish structural avoidance.

Reusable symbols carry canonical neutral JSON, explicit bounds, units, digest and
provenance. A PDF-only legacy resource can be retained in a scene contract but the
new shared renderer rejects it until a neutral variant is supplied. Assets are
expanded through one generic resolver; nested asset/text references in symbols
are explicitly outside profile1. New PDF streams use the existing pdfwriter
container without native compression dependencies. The legacy compressed writer
keeps its byte behavior. The capture bridge wraps existing floral primitive
mathematics, restoring ink state on success and failure. Full-page growth and
animation migration belongs to08. Existing old default path fingerprints remain
the compatibility authority. Tiny floral/tiling fixture definition versions move
to2 because their lowering/resource contracts change; graph remains1.

Cell fills do not stroke borders. The tiling fixture subsequently strokes each
global edge once using its stable edge ID, including the one shared seam.

## Text capability and explicit limits

The `positioned-outlines-v1` font profile requires Unicode clusters, real glyph
outlines, advances, bounding boxes, units-per-em, attribution and license. Text
operations identify semantic runs, an owned font resource, origin/size in cm and
each glyph's explicit offset. Concatenated clusters must equal the run's Unicode
content. Missing glyphs, divergent text, duplicate/missing runs and changed reading
order fail. There is no system-font or replacement-glyph fallback. This stage
consumes positioned glyphs; it does not claim shaping, bidirectional layout,
ligature discovery, caret navigation or the micrography work reserved for24.

Both outputs paint the same glyph outlines. PDF additionally contains a real
Type3 font made from those outlines, explicit widths/FontMatrix, ToUnicode CMap
and invisible positioned Unicode text, with ActualText for each run. Inherited
zero opacity suppresses Type3 painting; rendering mode3 alone is insufficient
under PDF1.7 section5.2.5. SVG embeds
the real renamed two-glyph OpenType subset and carries invisible text/tspans in
semantic reading order; visible geometry never depends on browser font fallback.
The outline font bank has1..255 glyphs; larger banks require a future profile.
XML1.0-disallowed control characters fail explicitly in the SVG serializer.
Reading order is the instance's logical run order, independent of paint order.
Selection/caret behavior in arbitrary viewers is not promised; Poppler raw text
extraction and SVG DOM order are mandatory checks. Pypdf local extraction also
recovers the ordered Unicode characters but may insert glyph-level line breaks.
This is searchable text, not a tagged-PDF accessibility certification.

The fixture is derived from Latin Modern Math1.959, GUST Font License/LPPL1.3c+,
separately from MIT code. See docs/fonts for the complete licenses, prominent
changes, original-work retrieval information and pinned font preparation recipe.

## Verification and numerical limits

`texlua tools/scenecheck.lua` produces six pairs: repeated real floral primitives,
graph plus traced strand, two tiles, clipping/winding/dash stress, monochrome and
positioned Latin/Greek text. Output directories bind all relevant Lua sources and
the actual font fixture. Atomic immutable byte publication verifies files before
and after rename; a busy lock or conflicting bytes fails. This is an atomic
visibility guarantee, not filesystem power-loss durability.

`python3 tools/scene_oracle.py` independently uses Inkscape for SVG and Poppler
for PDF at60 pixels/cm with identical explicit dimensions. It checks parsed SVG,
pdfinfo physical dimensions (0.02bp display tolerance), source/output digests,
absence of raster images, raw Unicode text order, DeviceGray operators and gray
pixels, analytic dash ink/gap and evenodd-hole samples. Mean absolute RGB error
must be below0.04 and one-pixel Gaussian-blurred error below0.025 (normalized
0..1). These bounded allowances cover raster antialiasing, color rounding and
stroke edge coverage, not missing features. Analytic probes catch local defects
that an average can hide. Each protected ROI separately requires every channel
at least254, with only a two-pixel guard against clipping-edge antialiasing.
The overlapping reservation's intersection is included in both ROI tests.
Local librsvg/Poppler comparisons are recorded separately and do not replace the
required Linux Inkscape check. Inspect the actual rendered fixture pages as well.

The legacy layout fingerprints and both TeX-host workflows remain required.
Finite fixture agreement is measured evidence for this profile; it is not a proof
of equivalence for every possible vector scene or PDF/SVG viewer.

A visual audit of initial CI41502953750 found that Inkscape1.4.2 lost the page backdrop for multiply paints inside clipped ancestor groups, even though the average error was within the fixed bounds. The corrected SVG serializer wraps each single paint and its active clip stack in an outer blend/opacity group. The group therefore blends against the page, matching PDF per-paint composition without filters or rasterization. The independent oracle now derives the interior multiply RGB color analytically and requires each channel within3/255; initial PDF90/81/98 passed, initial SVG177/94/101 failed against expected91/82/99. These local probes cannot be waived by a low global average.
