# Gothic tracery grammar

`ornament/gothic-tracery@1` implements a 2D profile of Havemann and Fellner’s VAST 2004 construction. It supports paired pointed bays, a crown with a tangent circular rosette, and a circular rose with rounded foils and recursive subdivisions. [Primary paper](https://doi.org/10.2312/VAST/VAST04/193-201)

The excess multiplies the window span to give the two arch radii. Their opposing centers lie on the springline. The upper circle intersection gives the apex, and the horizontal radius at each springpoint gives a vertical tangent to the jamb. Both half-span bays inherit the excess and use the requested lower springline. The source ellipse condition is solved on its vertical symmetry axis with a bounded monotone search. Four computed contacts split the corresponding arch arcs and share graph vertices with the crown circle. The generator rejects a contact outside the active arc.

The rounded foil radius follows the source’s sector tangent equation. Neighboring petals share their tangent feet, and each outward tip touches its enclosing circle. Each recursive child uses the same grammar within its parent foil’s circle and shares the outward tip. The profile supports up to two recursive levels with a 0.055 cm minimum foil radius. Arc centers, radii, signed sweeps and source dependencies remain in the construction graph.

Appearance uses a separate scene pass. Arch bands retain the circle centers, alter the radii by the physical offset, and recompute the apex for each contour. Circle bands are concentric. Foil outlines use bounded round-ended 2D strokes. Circular drawing segments use cubic Béziers of at most 45° each, and the independent tests sample their radial error. The diagnostic shows analytic centerlines and marked contacts.

This release profile covers the rounded foil construction and planar bands. It records the pointed-foil variant, historical profiles, extrusions and the source’s manifold mesh route outside this profile. Projected Gothic microarchitecture has its own Stage 26 requirements.
