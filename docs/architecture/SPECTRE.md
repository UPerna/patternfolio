# Spectre hierarchy and curves

The family tiling/spectre@1 uses the nine marked cluster rules in Figures
2.1 and 5.1 of Smith, Myers, Kaplan, and Goodman-Strauss. A fixed root
contains the cluster type, depth, edge length and world frame. Leaf
addresses record the source slot sequence. The base Gamma cluster
contains the two Spectres of the Mystic. The published hierarchy changes
handedness between levels. At odd depth the entire root is normalized
once, giving the same positive determinant for every final leaf.

Coordinates in the 30-degree lattice have integer coefficients in
(a+b sqrt(3), c+d sqrt(3))/2. Unit directions give the fourteen edges of
the equilateral outline, including both pieces of the collinear long
side. Anchor coincidences, turns, translations, lineage, and boundary
ownership are checked before numerical realization.

The spectre-s profile applies the centrally symmetric S-curve
construction of Lemma 2.1. It uses a cubic whose tangent offsets are
1/16 and -1/16 of a unit edge, at one-third and two-thirds along the
chord. Its exact controls have a common denominator of 192. The
projection along the chord is strictly monotone, and its central
symmetry makes the signed area correction zero. Opposite uses of an
edge reverse the same two controls. The finite checker tests separation
of neighboring cubic control hulls, allowing contact at a shared vertex.
Numerical realization uses binary64 with a checked 1e-10 cm comparison
tolerance. Curves are kept as cubics in both renderers.

The tile-1-1 profile emits the same source hierarchy with straight
edges. Its Build record identifies the weakly chiral Tile(1,1) diagnostic
with the source restriction to one handedness. The Hat is a separate
mathematical case whose tilings require reflections. The strictly chiral
Spectre claim refers to the smooth, centrally symmetric edge replacement
and the source theorem under its hypotheses.

The root is finite. Queries retain original whole tiles and their
ancestors. Global boundary records come from the entire fixed root, so a
cut created by a query has a different classification from its exterior.
Document views clip paint and preserve cell IDs. The reference comparison
covers Gamma depths one to three and Delta and Sigma at depth two. It
checks 8, 62, 488, 71 and 71 leaves against the authors' coordinate hashes.
The local independent audit reconstructs the hierarchy with high-precision
complex arithmetic and verifies unit edges, curve reversal, area and
finite incidence. It does not use raster appearance to infer chirality.

Primary source: David Smith, Joseph Samuel Myers, Craig S. Kaplan, and
Chaim Goodman-Strauss, A chiral aperiodic monotile, Combinatorial Theory
4(2), article 13 (2024), CC BY 4.0. Sections 2, 2.2, 4 and 5. Figures
2.1, 2.2, 5.1 and 5.3. https://escholarship.org/uc/item/4xn41982

Authors' reference: https://cs.uwaterloo.ca/~csk/spectre/app.html.
The implementation uses the published mathematical rules with original
code and render fixtures. The authors' app was used privately to verify
coordinate hashes. Its reusable code license is unverified and its code
and artwork are excluded from this repository.

Run texlua tools/spectrecheck.lua and python3 tools/spectre_oracle.py.
