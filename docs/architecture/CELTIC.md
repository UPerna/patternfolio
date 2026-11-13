# Celtic strands

The versioned registry family is strand/celtic@1. A specification supplies a
bounded straight-line planar embedding in centimetres, optional open sectors,
optional requested above branches, and an optional botanical port. Vertex and
edge identities are explicit. Graph validation rejects duplicate edges,
coincident vertices, vertex-on-edge degeneracies and crossing scaffold edges.
Coordinates use the shared filtered/exact orientation predicate for decisions.

The construction follows Kaplan and Cohen (2003), sections 3.1–3.3: each
scaffold edge creates one crossing and four oriented half nodes. The two
opposite same-label half nodes form one crossing branch. At a junction, the
right side of one outgoing edge meets the left side of its next CCW neighbor.
The resulting degree-two walks give stable closed components or two named
endpoints. At an explicitly opened sector its two ends become border ports.
A document crop clips paint only and adds no endpoints.

Section 3.5 motivates alternating encounters. An XOR graph constrains the two
branches of each crossing and successive encounters, including closed-cycle
wraparound, to opposite phases. Explicit pins join a common phase vertex.
Conflicts are diagnosed; stable branch ordering chooses unpinned phases.

Sections 3.3 and 3.7 motivate cubic Hermite geometry, the derivative magnitude
depending on distance, angle and user scale, and a directional chord blend
dampened at corners. This is an independently normalized version of the
heuristic. It preserves midpoint incidences and reciprocal tangents between
the two smoothed continuations; open lead segments and degree-one returns have
explicit constructions. Finite clearance tests sample 16 chords per connector,
using exact chord intersection classification. This detects the documented
unintended collision but is not a proof for all cubic pairs. Overpasses are
continuous paths; underpasses leave transparent gaps. Width/halo are paint
parameters and do not affect graph, strand, crossing or port identity.

The attached motif is a terminus, following the mechanism described in
section 4.1: a named open port owns a shared root and outgoing stem direction.
The actual Florilegium stem and leaf paint are anchored to that root and carry
the port reference. The interactive graph editor, all breakpoint styles,
spline alternatives, artistic sharpening, image interweaving/encapsulation
and illumination are outside this profile. No matching-figure claim is made.

Primary source: Matthew Kaplan and Elaine Cohen, Computer Generated Celtic
Design, Eurographics Symposium on Rendering 2003.
https://diglib.eg.org/server/api/core/bitstreams/281efea0-d74d-4444-8b60-1a4a2b0c7a98/content
Retrieved PDF SHA-256: 2e63f66c6311c6742813f9e9a2a3e7729d0e71a75a0058e548769235bd501272.

Validation: texlua tools/celticcheck.lua; python3 tools/celtic_oracle.py.
Fixtures cover two closed components, an open rectangular border, an
irregular wheel scaffold, and a stem/leaf attached to an open component.
