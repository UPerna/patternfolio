# Terms used in the platform

| Term | Meaning |
| --- | --- |
| Family | A registered pattern method with its own declared inputs, assumptions and validators. |
| Profile | A particular supported mode of a family or public generation workflow. |
| Recipe | Versioned data naming a definition, design inputs, seed, dependencies and document view. |
| Definition | The contract that declares a family's identity, parameter types and capabilities. |
| Design Specification | The validated design request supplied to the planner and generator. |
| Instance | The constructed geometry and its semantic relationships, before a page view is lowered to drawing. |
| View | Physical placement, cropping, protected regions and any declared projection of an instance. |
| Scene | Drawing operations and resources, with references back to the semantic instance. |
| Build record | Provenance, inputs, validation, outputs, budgets and lineage for one generation or replay. |
| Seed | A number that initializes the method's named random streams. |
| Replay | Validate a retained instance and rebuild its views without running its generator. |
| Canonical example | The preserved method fixture named in the catalog and evidence ledger. |
| Presentation variant | A separately named view or style, with its own recipe and provenance. |
| Protected region | A document rectangle reserved for content such as text. A family may treat it as a construction constraint or a clip in the view. |
| World frame | The stable construction coordinate system. Moving a crop does not rename its existing tiles. |
| Topology | Relationships such as graph connectivity, shared tile boundaries, strand crossings and logical text order. |
| Finite patch | A bounded generated sample. Its checks establish the properties tested on that sample. |
| Witness | Stored data demonstrating a particular admitted solution, which the relevant validator checks again. |
| Structural check | A test of relationships or geometric properties, distinct from a judgment of appearance. |
| Source fidelity | Which steps and assumptions of a referenced method the implementation follows, adapts or leaves outside its scope. |

The [contract reference](architecture/CONTRACTS.md) gives executable boundaries. The [source notes](research/SOURCES.md) identify references, adaptations and optional research extensions.
