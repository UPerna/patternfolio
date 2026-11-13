# Euclidean Islamic polygons in contact

The versioned registry family is `ornament/islamic-pic@1`. It uses the
periodic infrastructure for square, hexagonal, 4.8.8 and 4.6.12 scaffolds.
The scaffold and ornament graphs carry separate identities. Tile cycles
supply shared edges and stable contact IDs. The document planner clips
the view while preserving the world graph and its topology.

Kaplan's polygons-in-contact method starts two inward rays at each edge.
At zero displacement both start at the midpoint, on distinct coincident
branches. Across a seam each branch has opposite tangents. At positive
displacement the two origins separate by the supplied physical distance
and the rays point inward toward one another. A branch meets its reflected
direction in the neighboring tile. The shared position and declared
contact angle agree in both cases. Displacement must be strictly smaller
than every edge in the patch.

Each convex face collects forward ray intersections inside the polygon.
Opposing collinear rays are candidates with the straight-line cost.
Candidates are sorted by path length with deterministic ties and greedily
matched. Each accepted bend joins exactly two rays from distinct edges.
An unmatched ray rejects the construction. The angle input is bounded
to 1 through 89 degrees. Individual parquet contact angles may vary
linearly with world x and must stay strictly between 0 and 90 degrees.
The shared edge supplies the same angle to its incident faces. The
irregular convex gap fixture takes established angles per neighboring edge.

The 4.8.8 rosette transform insets each regular octagon, rotates it by half
an edge, and joins the inset vertices to the original midpoints. The
radius uses the Section 4 formula. Each square contributes its perpendicular
bisectors. Around a complete old vertex, the two octagon wedges and the
square wedge make one pentagon after erasing old boundaries and merging
collinear spokes. The verifier checks the inset radius, spoke lengths,
face provenance, the area of the original wedges against each replacement
pentagon, and the shared contact geometry. The inset and pentagon faces
receive fresh PIC motifs. The default ratio reproduces the equal-length
construction. Other admissible ratios are explicitly controlled variations.

The profile covers Euclidean convex scaffolds, the transformed octagon and
pentagon construction, and convex irregular-gap inference. The renderer
draws continuous centerlines without assigning over/under states to
geometric crossings. Hyperbolic and spherical motifs, second-pass inner
inference, generalized nonconvex gap subdivision, and historical
authenticity are outside the profile.

Primary sources

- Craig S. Kaplan, Islamic star patterns from polygons in contact,
  Graphics Interface 2005, sections 3, 3.1 and 4.
  https://cs.uwaterloo.ca/~csk/publications/Papers/kaplan_2005.pdf
- Craig S. Kaplan and David H. Salesin, Islamic Star Patterns in Absolute
  Geometry, ACM TOG 23(2), April 2004, sections 4.2 and 4.3.
  https://cs.uwaterloo.ca/~csk/publications/Papers/kaplan_salesin_2004_b.pdf

Retrieved PDF SHA-256 digests are R04a 661bfc90cc679eebfaccd2f12024a310905e56d6488436c899794947ca2b5e65 and R04b cb4d4c76ee780cd909e6076e70936671136e16d7d68c5db806da3bc6c197419d. Run `texlua tools/islamiccheck.lua` and
`python3 tools/islamic_oracle.py` for structural and visual evidence.
