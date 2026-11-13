# Performance and bounded execution

Stage 34 working report. Native CI, browser measurements and publication acceptance remain pending until their receipts pass. A prepared recipe is not evidence that its generated result passed.

The local 27-workload matrix and three alternating before/after pairs completed successfully; see PERFORMANCE-MEASUREMENTS-34.md and their raw source fingerprints. The local full browser attempt completed all 27 workloads and 54 limit/cancellation cases, then failed its final studio test. That test exposed stale floral host-packet seeds after a seed edit. The native editor now synchronizes the host packet and design seed for both authored and grown legacy families. A new native regression checks both actual generators and byte-exact stored-instance replay; a focused Edge check now passes editing and cancellation with the synchronized seed. The original failed browser receipt is retained. The seed repair is outside the timed generator/replay paths; local measurements remain bound to their actual pre-repair source manifests rather than being relabelled as current-code results. Exact-head CI reruns the complete matrix, browser/studio checks and inherited gates after the repair.

## Method

`tools/perf_prepare.lua` builds 27 recipes through the public definition, design specification, document context and planner APIs. Nine classes have small, medium and large inputs: floral growth, knot topology, circle packing, substitution, projection, optimization, mosaic packing, text shaping and example synthesis. These are finite workloads, not universal complexity guarantees.

`tools/perf_bench.py` runs fresh child processes serially with a 300-second wall limit per workload. `tools/perf_run.lua` measures cold generation, warm generation and validated stored-instance replay, followed by actual PDF/SVG serialization. Replay disables the registry generator. Actual instance and scene bytes must agree in all three phases. Receipts include input and complete shared-source hashes, times, object counts, output sizes, budgets and Lua allocation snapshots. Measurements stay outside semantic hashes. `--resume` reuses only successful receipts whose full source and recipe descriptors match.

The local host is Python 3.12.14 / Lupa 2.8, Lua 5.3, Windows 11, AMD Ryzen 5 PRO 5675U, 12 logical processors and 15,886,311,424 bytes physical RAM. This is the shared core with real pure-Lua SHA, not native TeX. Lua allocations are capped at 256 MiB, excluding Python/OS allocations. After-collection snapshots are separate from uncollected transient allocations; neither is an exact phase peak or whole-process working set. Power, temperature and other system activity are uncontrolled. CI records its own actual runtime and times.

The browser runner uses the same Lua through Wasmoon 1.16.0 and hash-wasm 4.12.0. Each request has a fresh worker; warm means verified client/assets reused, not a persistent solver session. The existing binary-safe host SHA bypasses the new pure-Lua cache. Worker Lua memory, main-thread heartbeats and elapsed times are separate. No Pi, mobile, other browser, other OS or physical print performance is inferred.

## Profile-driven changes

Sampling attributed 82.95% of periodic samples and about 48.63% of Micrography samples to SHA. Hook overhead prevents treating profile times as throughput. One serial unprofiled periodic observation before byte reuse took 3.91 / 4.17 / 4.83 seconds for cold/warm/replay; after reuse, 2.91 / 1.68 / 1.74 seconds, with identical instance and scene hashes. These are individual observations. Repetitions and the full matrix must be assessed separately.

The SHA FIFO keys complete immutable Lua strings. Retained input payload is at most 4 MiB, entry count 256 and single cached input 2 MiB. Larger admitted inputs bypass reuse. The original 64 MiB guard and compression remain. Caller-owned tables, coordinates and supplied digests are never keys. This operational cache is distinct from structural, render, solver and browser result caches. Independent Python vectors, binary boundaries, eviction, memory pressure and caller-table mutation controls exercise both Lua 5.3 and 5.4.

Actual zero-object-limit tests exposed missing object charges for mosaic sites, shaped text graphemes and example-synthesis grid samples. Those families now charge the requested or shaped object count before their expensive solves. The algorithms and generated geometry are unchanged; exhausted requests must fail without accepted outputs. The pre-fix observations and subsequent full-suite results remain separate evidence.

Scaling exposed false rejection of a valid 60-spoke packing: naive normalized angle accumulation differed from the recorded residual beyond the existing 1e-14 receipt bound. Compensated accumulation agrees with independent Python `math.fsum`; the analytic radius ratio is also checked. Only validator summation changed: solver, circles, geometry, 1e-11 tolerance and 1e-14 bound remain. Corrupt residual, radius and position controls still fail. The same packing's full ornament subsequently rejects unmatched PIC rays at 72 degrees, with no accepted output. The input and both rejected observations remain visible.

## Workload scope

Floral sizes are quarter, half and full A4 linear dimensions, fixed density 0.3 and consistently scaled canonical host geometry. An earlier full-A4 small-labelled case at density 0.2 passed in 98.996 seconds for the whole child; it remains exploratory evidence. Revised inputs measure physical page-area scaling.

Knot grids have 3, 5 and 8 vertices per side spaced 2 cm apart. The initial 1 cm fixture failed ribbon clearance; no clearance tolerance or smoothing implementation was changed. Packing uses hexagonal triangular disks of 7, 19 and 61 circles. Substitution depths are 2/3/4; projection areas 2×2, 4×3 and 8×6 cm. Optimization uses 24/120/360 steps; mosaic targets 24/96/192 objects. Text has 123/433/1394 characters; example synthesis uses 4/12/24 subdivisions and 9/17/33 rows. Exact recipes and hashes are retained.

The initial large text panel was 13×18 cm and rejected as `micrography-field-not-horizontal-monotone`. That failure and exact recipe are retained. The large benchmark now uses a 26×14 cm panel with the same text length, exercising text scaling within the admitted field profile rather than loosening its validity requirement.

Existing recursion, text/import, instruction, allocation, transport and output bounds remain. `check-performance-bounds.lua` exercises three actual cancellation checkpoints and object/operation/byte exhaustion across all nine classes. `browser-performance.cjs` exercises two progress cancellation points, two instruction limits, low memory and a watchdog across all nine large cases. Exhaustion must have zero accepted outputs. Heartbeat/click observations describe actual main-thread responsiveness, not an invented latency guarantee. Persistent browser-cache round trips compare actual asset bytes.

## Reproduction

```sh
texlua tools/check-hash-cache.lua
texlua tools/check-packing-scale.lua
texlua tools/perf_prepare.lua
texlua tools/check-performance-bounds.lua
python3 tools/perf_bench.py --label measured
texlua tools/check-floral-editor-seed.lua
```

CI retains every inherited structural, export, source-kit, editor and native/browser parity gate and adds native and browser performance checks. Exact-head CI and actual-artifact review remain mandatory. Working observations and rejected experiments are in receipts34. Complete the matrix, repetitions, browser results and practical defaults before accepting this report.
