# Deterministic recipe and build profile 1

Run `texlua tools/replaycheck.lua` and `python3 tools/determinism_oracle.py` from
the repository root. They exercise real floral, graph and tiling builds, malformed
inputs, independent golden vectors, dependency mutations and actual filesystem
faults. `make check` and the required CI PDF job run them without replacing the
existing regressions. Lua 5.3/int64/binary64 is the first supported core profile;
local checks also run Lua 5.4 with that numeric profile. The [browser runtime](BROWSER-RUNTIME.md) describes the shared implementation and named comparison tolerances.

## Recipe and strict input

`pattern_recipe.new` validates `{kind="recipe",schema_version=1,id,definition,
design,view,dimension,dependencies}`. Definition and Design Specification reuse
the contracts; the view is an input template without an instance reference.
`from_specification` constructs a recipe from existing validated examples.
`decode`/`encode` round-trip validated recipes. Unknown record controls, unknown
versions, invalid ranges, nonfinite numbers and ambiguous units fail. Source
document regions are construction inputs; viewport crop belongs to the view.

`pattern_parse` implements bounded RFC 8259 grammar with dkjson decoding only
validated quoted strings. It rejects decoded duplicate keys (including escape
aliases), comments, missing/trailing commas, bad number syntax, nonfinite
conversion, null, control characters, invalid UTF-8 and unpaired surrogates.
Limits: 2 MiB input, 60 nesting levels, 100,000 values, plus contract data limits.
There is no executable expression or implicit external-file access in JSON.
Inputs and constraints still require the owning generator's validation callback.

Schema 1 currently has an explicit identity-validation migration with an input
digest receipt. No older schema has an invented conversion: migration from 0 or
to an unsupported version fails. Future converters must be separately named and
validated; preserve the original input and record changed semantics.

## Canonical bytes, hashes and streams

The `pattern-canonical-v1` profile orders object keys by UTF-8 bytes, retains
array order, preserves Unicode codepoints without normalization, spells all zero
as `0`, and uses 17 significant digits for binary64 numbers. Decimal separators
are `.` and exponents use lowercase `e`, an explicit sign and no leading zeros.
It is a project profile, **not RFC 8785/JCS**. Integer identities outside the
portable exact range must be strings. Golden number vectors and available locale
changes check spelling; browser vectors are not considered passed until run there.

`pattern_hash` independently implements SHA-256 using masked 32-bit words under
Lua's int64 profile. Raw content digests use `sha256(bytes)`. Domain hashes use
`bytes(domain,payload)` or `value(domain,data)`: prefix `pattern-platform`, NUL,
`hash-v1`, NUL, then decimal byte length, colon, domain, decimal byte length,
colon, payload. `value` first serializes canonical bytes. Distinct domains cover
instances, recipes, cache layers, source manifests and stream derivation.

`pattern_random` uses version `pm16807-schrage-v1`. Named stream seeds derive
from the domain-hashed root seed, definition/version namespace, stream name and
stable semantic identity. The first digest word reduces into the valid seed
range. Each context retains separate stream state; requesting another semantic
stream cannot consume it. This is deterministic state isolation, not a claim of
collision-free seeds or cryptographic/statistical independence. Seeds and IDs
never derive from time, traversal order, locale, viewport or rounded coordinates.
The Schrage step keeps intermediates in signed 32-bit range; the full existing
Lua core and SHA module currently require int64/binary64. No global RNG is used.

`determinism-v1.json` fixes SHA padding/binary/million-byte cases, numeric spelling,
byte ordering and named streams. The Python oracle independently uses hashlib
and modular integer arithmetic; it verifies the committed vectors and never
rewrites them. The published 10,000th PRNG value is also checked directly.

## Dependency layers and exact byte provenance

`environment(source,runtime,renderer,input_bytes)` hashes actual source bytes,
not caller-asserted source digests. Source files are grouped by construction,
style, view and renderer consumption. It records revision or explicit dirty-tree
identity, per-file SHA-256 and a manifest digest. Runtime and renderer identity
and versions are explicit. The fixture conservatively binds all root Lua modules
plus its generator source; later hosts must enumerate every actual dependency.
An untrusted plugin cannot be made trustworthy merely by a self-declared manifest.

Each dependency group maps named inputs to `{sha256,version?,configuration?}`.
The environment hashes supplied input bytes. Execution rejects missing/mismatched
bytes and unused supplied inputs; generators use `context:input(name)` only for
declared construction dependencies. Lowering can access declared drawing inputs.
Raw binary inputs stay outside serialized metadata; receipts retain their hashes.
Fonts and shaping settings that affect placement belong in construction; a font
used only by paint belongs in the appropriate drawing layer. Solver result bytes
and solver configuration/version are construction dependencies. New hosts must
verify exact bytes before consumption, rather than trusting a filename or mtime.

| Key | Actual dependencies |
| --- | --- |
| structure | full definition, construction Design Specification, dimension, seed/PRNG/hash versions, construction source/data, runtime and observable execution budgets |
| style | structure key, palette/style, style source/data |
| view | structure key, placement/crop/projection/protected regions, view source/data |
| renderer | style + view keys, renderer source/data, renderer identity/version |

Generation receives an empty style object; style cannot secretly alter topology
through this pipeline. Changing the viewport retains the construction document
and instance. Runtime changes invalidate construction and all downstream keys;
renderer-only version changes invalidate the renderer key. A documentation-only
Git revision change need not invalidate unchanged source products, but the new
Build record still binds that revision. Timing, timestamps and artifact container
metadata are excluded from semantic keys.

`execute` validates the registered definition against the recipe, configures
named streams, validates the instance, applies the view and lowers the scene.
It returns accepted bytes only on completion. Complete Build records require
source-manifest and exact input/output byte digests, plus actual validation.
Failed/cancelled builds retain diagnostics and budgets and return no accepted
instance/scene. Partial status is explicit and cannot masquerade as complete.
Record IDs hash their body before adding the ID, including outcome and budgets; records do not contain their own digest. Outputs may be hashed later without a
commit-hash self-reference. A host must preserve source snapshots for replay;
hashes alone cannot reconstruct missing bytes.

## Atomic publication and cache integrity

`pattern_store.new(directory,host?)` stores immutable UTF-8 payloads under a
SHA-256 layer key. The default TeX host uses LuaFileSystem atomic directory
creation plus same-volume rename. Other hosts must provide the explicit atomic
filesystem interface; there is no direct-write fallback. The caller owns/creates
the cache directory and confines paths. Browser storage requires a transactional
host adapter at 31; no filesystem assumption enters generators.

A writer acquires `<key>.json.lock`, writes inside that directory, flushes/closes,
verifies all temporary bytes and renames to the final file. Readers only inspect
final files and verify key/schema/payload digest. Duplicate identical writes are
safe; different payloads under one key fail. Corrupt entries require explicit
quarantine. Busy/stale locks are visible and are not deleted by another writer.
Crashes before rename leave no accepted entry. A successful rename is atomic
visibility, not a claim of power-loss durability: directory fsync is not exposed
by standard Lua. The directory must be on a filesystem with the advertised atomic
operations and all writers must use this protocol. Payload limit is 1 MiB and
escaped envelope limit 2 MiB; larger products fail explicitly. No half-written
entry is a cache hit. Individual products are committed separately; a Build
record claiming a group must be published only after all its product writes pass.

## Replay scope and preserved legacy behavior

Actual examples demonstrate repeated recipes producing equal instance/scene
bytes, palette changes preserving tiling geometry, crop changes preserving the
same tile IDs/geometry, and verified input bytes affecting actual graph geometry.
The floral replay fixture draws real `flora.flower` and `flora.bee` primitives
with one owned legacy primitive RNG per named semantic identity. Adding the bee
between two flowers changes neither flower stream nor drawing bytes.

This does not claim full-page floral migration. Existing `grow.lua` has visitor
occupancy and shared draw-stream interactions; its page fingerprints are retained.
Stage 08 must handle migration with explicit compatibility evidence. The stage03
PDF-only floral interop resource still uses fixed fixture colors and rejects
unimplemented palette controls. General floral palettes/semantics, real fonts,
solvers and browser execution remain their owning implementation gates.

## Document planning extension, stage07

Old schema1 recipes retain their exact encoding and execution path. New document recipes use planner.recipe and view.extensions.document_planning schema1, containing validated document/profile/page/options inputs. They store no stale cell-selection list. DesignSpecification.extensions.planning_generation binds the actual construction frame/profile; adaptive mode also binds actual page geometry, anchors and host snapshot. This data is immutable context metadata and part of the construction key. Fixed crops/reservations remain in view inputs. Recipe validation recomputes normalized physical context; execution plans and lowers the newly validated instance and records that evidence in the BuildRecord. Missing or mismatched context, failed full-tile/halo policy, physical constraints or cancellation cannot produce a complete build. Use planner.recipe with document inputs instead of feeding a computed planner view into the old from_specification helper.
