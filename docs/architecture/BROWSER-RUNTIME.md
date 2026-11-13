# Browser shared-core host (stage31)

The static source bundle runs the actual root Lua modules inside a fresh dedicated
worker for each request. JavaScript transports bounded bytes, supervises work and
computes SHA-256; it contains no geometric construction, validation or rendering
port. The editor belongs to stage32. Hosting, merging and release remain stage39.

## Runtime selection and provenance

Wasmoon1.16.0 embeds Lua5.4 with int64/binary64. The npm package source is
87c783a8d0bf65afeda933fa47d8dc996be53bb3; its Lua submodule is
be908a7d4d8130264ad67c5789169769f824c5d1 (lua.h names5.4.5). The binary itself
reports Lua5.4, without a patch number. Its exact raw Wasm hash is pinned in
web/vendor/manifest.json. Preserve both the SDK MIT license and the exact Lua
1994–2022 MIT notice. The loader is151652bytes (38945gzip), Wasm271581bytes
(110637gzip). First desktop Edge cold factory measured43.4ms; primitive probe
startup48.6ms. These are observed local measurements, not universal targets.

Fengari-web0.1.4 is smaller as a combined219632byte JavaScript file (69755gzip),
but its actual browser math.maxinteger is2147483647. Loading the unchanged
pattern_hash module fails the required int64/binary64 guard. It is rejected;
the shared numeric/PRNG guard is retained.

The first pure-Lua SHA route produced the correct periodic bytes in15.5s, but
full authored work timed out at300s. Profiling measured2.87411B of4.00001B
opcodes inside SHA. hash-wasm4.12.0 adds18616bytes including its embedded Wasm.
Its package Git source is373b796205ab55fb4a657374dad6ea589bf75815. Both MIT and
the embedded C SHA-256 notice are included. The pinned Wasmoon raw C API passes
Lua string pointer/length directly to the synchronous SHA implementation:
no UTF-8 conversion is permitted. The ordinary shared Lua SHA module and its
integer guard remain unchanged; only the worker's private host SHA primitive is
replaced. Independent Node crypto vectors include arbitrary byte strings,
SHA padding/block boundaries and one million bytes; production worker callback,
PRNG and canonical UTF-8/numeric probes are exercised in browser-adversarial.cjs.

Accelerated periodic measured5.57s; full authored measured144.75s in development,
4.75365B Lua instructions,73.54MB final observed Lua allocations and30,860,147
output bytes across143 assets. Its instance/PDF/SVG hashes exactly equal the
accepted native stage30 output. A later all-family run measured154s generation
and179s replay for authored. Timings/resource profiles are receipts, never
canonical geometry. Stage34 must measure workload classes/defaults separately.

## Protocol, resource and trust boundaries

pattern-browser-v1 envelopes carry schema_version1, request_id and generation.
Init/ready precede execute; inputs/shared-core progress, assets/asset-chunk,
structured error or complete follow. The public client accepts capabilities,
schema, validate, generate, validate-instance, render, replay and diagnose. Lua
calls pattern_cli_core.dispatch; no successful result is a truncated patch.
Generation/request identities and worker identity gate every response. New work
supersedes old work; cancellation and watchdog abort terminate the worker.
Late asynchronous digests cannot resolve an old pending job.

Host maxima:32MiB inputs,64MiB outputs,1024 files,256KiB chunks,2MiB request
header,100000 message nodes and depth60. Core requested budgets above100000
objects/48000000 operations/64MiB are rejected rather than clamped. The strict
Lua parser and all family validators retain their own bounds. Default instruction
limit16B, configurable1000..32B; a10000-instruction hook latches failure even
when an inner generator catches a Lua error. Default/max watchdog300000ms;
expiry is an abort, never a detail-reduction rule. Host hashing is limited to
64MiB per call,512MiB total and1M calls. The runtime record binds the actual
UA and host configuration by SHA-256; full values appear in resource evidence.
This fits the existing256byte stable-ID contract.

Lua allocation ceiling defaults256MiB (configurable2..256MiB). This is the
VM allocator's traced ceiling, not a claim that the entire browser process uses
256MiB. Source/transport/JS buffers have the separate finite size/count bounds
above; browser/JIT/Wasm allocator overhead is outside the Lua counter. Workers
are terminated after every job. Failure produces no accepted partial assets.

The trusted static loader checks every worker/vendor/Wasm/bundle digest and root
Lua source digest before use. Worker module search is preload-only; filesystem,
process, dynamic-loader and debug globals are removed after trusted bootstrap.
Only JSON recipes/instances reach the public client; arbitrary user Lua is not
supported. This is an application worker trust boundary, not a claim that a
hostile same-origin script or replacement root manifest is sandboxed by Lua.
No CDN, API key, backend or HTTP request is used for ordinary execution after
assets load, including cancellation/restart. Actual browser offline mode tests
fresh workers. Native-process solver providers are explicitly unavailable;
bounded pure-Lua solvers and independently validated supplied instances can replay.

IndexedDB captures a private structured clone before any asynchronous digest, then stores complete immutable bundles in an atomic readwrite transaction. A caller buffer/manifest mutation during save is exercised: the original captured bytes remain readable. The initial candidate failed this race and remains unaccepted; the repair preserves the initial corruption evidence.
Concurrent identical puts reuse one record; conflicting contents abort and retain
the original. Reads recheck binary hashes and metadata/source/cache identity.
Corrupt, empty or partial bundles fail. Cache availability is optional; choosing
an explicit cache makes transaction failure visible rather than claiming a save.

## Comparison and reproducible checks

Build with python3 tools/webpackage.py, serve build/web on loopback, and execute
node tools/browsercheck.cjs with a native CLI receipt and Playwright module path.
The browser CI job depends on the actual same-checkout pdfs job and checks its
CLI source fingerprint. tools/clicheck.py retains native numerical fixtures.
All22 families generate and replay in a real browser; every replay must preserve
its own instance/PDF/SVG bytes exactly. Twenty native comparisons are byte exact.
Micrography and Decobrush contain host-libm-sensitive derived floats, so their
native instances, SVG trees and PDF operators/resources are compared independently
by tools/browser_parity.py. Text, IDs, array order, keys, integer topology, font
resource streams and operation structure stay exact. Float differences are
admitted only in the named numerical instance subtrees and numeric vector
operands, bounded by min(1e-10,32*binary64_epsilon*max(1,abs(a),abs(b))). This is
stricter than the existing stage05 relative geometry policy for these cm-scale
fixtures. No coordinates or expected hashes are rewritten. Controlled numerical
drift/topology/text/order corruptions must be detected. Initial local differences
were at most2.23e-15 (micrography) and1.12e-16 (Decobrush).

browser-adversarial.cjs records actual cancellation, supersession, protocol/input/
depth/object/instruction/memory/watchdog failures, recovery, offline restart,
immutable-cache conflict/concurrency/tamper, and explicitly labelled controlled
response injection for stale/empty/offset/resource cases. Primitive conformance
uses trusted test-only bootstrap instrumentation at session entry to exercise
the actual production worker raw-byte hash callback; arbitrary user Lua remains
outside the public API. Source-kit consumption rebuilds every browser asset from
the extracted archive and requires exact hashes/licenses.

Actual desktop evidence so far: Windows Microsoft Edge156.0.4314.58, Playwright
1.62.1. Fresh Linux Chromium CI evidence is pending. No Firefox/Safari/mobile/Pi
support or performance is claimed. Stage31 remains in progress until exact-head
native/browser CI, source archive/tree verification and acceptance are saved.
