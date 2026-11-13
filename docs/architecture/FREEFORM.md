# Finite freeform Islamic ornament

The registry family is ornament/islamic-freeform@1. It implements the finite
circle packing route in Lin and Kaplan, sections 3 and 4. The input is an
oriented simplicial disk. The current profile supports up to 120 triangles
and 72 vertices, with positive degree-based boundary radii. It checks
edge incidence, orientability, Euler characteristic, vertex links, and one
boundary cycle before solving.

The source fixes a boundary radius at csc(pi/(2d-2))-1 for vertex degree d.
This implementation independently solves the same interior angle equations
with deterministic successive log-space bisection, instead of copying a
third-party implementation. It embeds the tangent triangles from the first
oriented edge. Every prescribed tangency and every nonedge clearance is
checked. The residuals are numerical and are retained in the packing
certificate. A rectangular panel scales and translates the entire circle
envelope before polygon and motif construction. The inspected panel also
has space for the actual stroke width within its requested bounds.

Each interior circle supplies a scaled cyclic polygon with alternating
tangency directions and arc midpoints. A triangle supplies three filler
pentagons meeting at its incenter. The finite profile keeps these pentagons
and the interior cyclic polygons, exposing boundary contacts where an outer
cyclic face is omitted. The independent checker verifies this patch as a
disk and checks pairwise separation of its convex polygon interiors.

A wheel connects alternate edge midpoints by a bend on its inner circle.
The angle-to-radius relation is Eq. 2. The radius approximation uses the
scaled circle corresponding to the actual tau-controlled polygon. The filler
PIC rays copy the actual wheel directions across shared contacts, including
asymmetric contacts, and use the global angle at filler-to-filler edges.
An inadmissible wheel or unmatched filler ray fails with its own diagnostic.
The present profile uses convex fillers and continuous vector centerlines.

A solved packing may be supplied as input to a saved recipe. Replay verifies
the certificate and reconstructs the graph without invoking the radius solver.
The Build record includes algorithm version, convergence status, iteration
count, tolerance, residuals, boundary rule and normalization. A failed solve
produces a failed Build record with its diagnostic. Native visual artifacts
include the original twelve-point fan, the edited nonperiodic arrangement with
six- and fourteen-point rosettes, and its constrained panel.

The optional gadgets, periodic/toroidal extension, and crossing decoration
have separate scopes. The finite implementation does not claim them.

Primary source: Rebecca Lin and Craig S. Kaplan, Freeform Islamic Geometric
Patterns, sections 3 and 4.1-4.4. The retrieved PDF has SHA-256
ae7ba5f35695f517ceeae774f54200d1eac98837bf8a86d6d23c147aa0d5531c.
Use the R05 record in docs/research/SOURCES.md for its primary link.

Run texlua tools/freeformcheck.lua and python3 tools/freeform_oracle.py.
