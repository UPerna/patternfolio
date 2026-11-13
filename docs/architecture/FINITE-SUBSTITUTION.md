# Finite aperiodic construction routes

The route registry accepts providers for hierarchical substitution,
projection/multigrid, and bounded constraints. A route is reported as
implemented only after a provider supplies construction and verification.
The exercised provider is tiling/finite-substitution@1, an integer
L-triomino fixture. Projection and bounded constraints are still explicit
unsupported routes in this provider.

The prototype occupies unit squares (0,0), (1,0), and (0,1). Its eight
directed boundary segments carry stable local labels. Adjacent uses of a
physical segment have opposite directions. These labels describe the
prototype boundary and do not impose aperiodicity. The provider permits
integer translations and orientation-preserving quarter turns.

The inflation factor is two. The four child transforms, written as
quarter-turn count and integer x/y offset, are (0,0,0), (0,1,1), (1,4,0),
and (3,0,4). An exact check partitions the inflated twelve-unit-square
prototype. An independent exhaustive search recovers the same dissection.
The depth-four root has 256 leaves covering 768 distinct unit squares.
The root is an L-shaped union of two rectangles. The empty corner belongs
to the exterior of the finite horizon.

A request fixes its world frame, leaf scale, and root depth. Address letters
identify the path from root to leaf. A query keeps complete leaves whose
squares intersect its halo and retains their original ancestors. It cannot
extend past the certified horizon. Adjacent queries can share world edges
even when one omits a neighboring tile. Global owners and neighbor IDs come
from the whole bounded root. Present edges distinguish true root boundaries
from query cuts. Document views crop the paint and retain the source
construction. The same physical window from two independent patches must
have byte-identical PDF and SVG, and pixel-identical rasters.

The Build record carries the source rule, assumptions, root identity, finite
horizon, halo, and checks performed. Reflection, duplicate occupancy,
altered seam coordinates, and broken ancestry are deliberate rejection
fixtures. The certificate establishes a finite dissection and makes no
claim to a globally queryable infinite tiling.

Sources

- Natalie Priebe Frank, A primer of substitution tilings of the Euclidean
  plane, Section 2.1. https://pages.vassar.edu/nafrank/files/2012/08/substitutions.pdf
- Multidimensional color codes for chair tilings, Acta Crystallographica A
  78 (2022), Fig. 4. https://doi.org/10.1107/S2053273322004065

Run texlua tools/substitutioncheck.lua and python3 tools/substitution_oracle.py.
