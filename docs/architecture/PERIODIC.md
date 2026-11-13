# Periodic tilings and symmetry

The registry definition is `tiling/periodic@1` in `pattern_periodic.lua`.
It supports square, triangular and hexagonal tilings and two selected mixed
scaffolds from Kaplan's polygons-in-contact examples: 4.8.8 and 4.6.12.
The numbers give the polygon side counts at a vertex. Nonuniform examples in
the same paper and its later motif construction are not implemented here.

A Design Specification selects the family, lattice step in cm, rotation in
degrees and optionally an admitted wallpaper group. The step is the length
of each primitive basis vector; it need not equal the tile edge length.
The context supplies a fixed 2D cm world frame and origin. In the square
chart the basis vectors meet at 90°; in the hexagonal chart they meet at 60°.
Only uniform scale and rotation realize the chart. Physical document crops
never supply the lattice origin or change that metric.

## Exact templates

The finite quotient stores complete prototype polygons and their addresses
relative to one primitive translation parallelogram. A vertex is four
integers encoding `((u0+u1 sqrt(D))/6, (v0+v1 sqrt(D))/6)`; D is 2 or 3.
Its stable ID uses those coefficients, not a rounded rendered point.
The integer address (i,j) adds (6i,6j) to the rational coefficients.
The actual world point is the binary64 evaluation in the fixed metric frame.

4.8.8 truncates unit-square corners at a fraction 1−sqrt(2)/2 of each side.
This leaves equal octagon edges and one regular square gap per unit domain.
4.6.12 uses the incenter of the p6m chamber with fractional coordinates
(0,0), (1/2,0), (1/3,1/3). The seed is (1/3,(sqrt(3)−1)/6).
The stabilizers about these three corners produce a dodecagon, square and
hexagon; rotations and translations give one dodecagon, three squares and
two hexagons in a primitive domain. All template geometry uses exact
quadratic coefficients.

The quotient checks convex positive polygons, equal edges, equal turns and
oppositely directed paired edges with exact translated endpoints.
The summed area equals one lattice domain exactly. Every potential positive
overlap is ruled out by comparing all relative shifts in ±2 on both axes;
the exact coordinate span of the templates is at most two lattice units.
This suffices for the infinite translated construction. The polygon union
is locally finite and closed, so an uncovered point would have a
positive-area open neighborhood, contradicting the exact area and
nonoverlap. The independent oracle recomputes areas, vertex configurations,
seams and separating-axis checks. A finite view alone is not this proof.

## Queries, ports and views

The generator inverts the world query to a conservative integer window and
includes an extra ring beyond the template support. A bounded request
enumerates complete cells; it does not create cropped topology.
The profile admits at most 1536 cells and addresses within ±32768.
The document planner requests coverage plus its conservative tile halo;
it rejects insufficient coverage rather than substituting another pattern.

A global edge has one canonical endpoint order, an exact seam equivalence
class and a theoretical global owner. If the global owner is outside a
finite patch, the contract's incident owner is the present cell and the edge
is labeled a patch boundary. This does not change its global identity,
canonical direction, neighbor address or ports. Interior edges are stroked
once. Views may crop or mask paint without changing the underlying topology.

Each edge records its midpoint port. `pattern_periodic.port(instance,
cell_id, edge_index, numerator, denominator)` accepts a bounded interior
rational position in that cell's directed edge. It converts to the canonical
edge direction, reduces the fraction, and returns a stable ID, exact lattice
coefficients and the world point. Opposite cell directions use t and 1−t
and resolve to the same port. Later motif families can attach to those
identities and use the declared edge correspondences.

## Wallpaper scope

The exact affine registry implements p1, p2, p3, p4, p4m, p6 and p6m.
The last two mirror-group spellings follow common abbreviations; the IUCr
symbols are p4mm and p6mm. Each operation has an integer 2×2 matrix, a signed
orientation and an optional integer translation. Composition and inversion
are exact in the lattice chart. Unsupported groups and incompatible metrics
fail explicitly. The registry verifies that the chosen operations preserve
the actual polygon quotient; this is a geometric property and does not
assert that arbitrary colors or asymmetric markers preserve every symmetry.
The IUCr 120° chart maps from our coordinates as (x,y)=(u+v,v).

`texlua tools/periodiccheck.lua` generates the five standard views, two
independent overlapping queries, a translated patch and an actual saved
full-tile recipe with a protected region. `python3 tools/periodic_oracle.py`
checks exact quotient facts, actual world geometry, edges/ports, independent
Inkscape/Poppler output and the common world pixels. The native CI gates
retain all earlier geometry, rendering, botanical and TeX checks.

The renderer keeps world path coordinates and applies the view matrix at paint time.
Stroke width is supplied in construction cm and transformed by the view. The overlap
oracle compares exact common world paths and renders an identical physical crop
from each independent patch; both vectors and pixels must match. It separately
reports antialias differences between distinct viewport clips. The initial local
SVG probe differed in 7 of 17,056 pixels (peak 4 channel levels); the PDF and
identical physical viewport probes were pixel exact. This diagnostic is retained
in the stage receipt.
