# Practical defaults and measured limits

The existing browser limits remain: five-minute watchdog,256MiB Lua allocations,16billion metered instructions,32MiB input transport and64MiB output transport. All27current-code local workload cases passed within these limits. The observed maxima below describe the actual recorded Windows/Edge run; they are not portable latency targets or peak/whole-process memory claims.

Largest measured browser request: text-shaping-large / warm-assets-generation, 42.128s. Largest completion Lua allocation snapshot: 30.68MiB (circle-packing-large). Largest metered request: 2061290000 instructions (text-shaping-large).

Retain tested canonical editor starting recipes and existing hard bounds. Use measured small/medium workload inputs as conservative starting points; increase one construction parameter at a time. Do not raise caps automatically, truncate topology, or present exhausted/invalid inputs as complete. A profile admission maximum is not a latency or convergence guarantee. Use saved-instance replay for repeated placement/style and preserve structural validation. No other-device performance inference.

The byte-hash FIFO retains at most4MiB of immutable input payload,256entries,2MiBperentry. Oversized admitted hashes bypass reuse; the64MiB SHA admission limit remains. Larger page/vector inputs may therefore gain less from reuse. Structural/render/solver/browser caches remain distinct. Exact replay is validated, not trusted solely because data came from a cache.

The actual text inputs contain123/433/1394ASCIIcharacters. Earlier prose counts were incorrect; raw recipes, generation and measured semantic object counts were unaffected. The correction is retained for the next source checkpoint.

Exact-current-head nativeCI and artifact review remain mandatory. Physical print/mobile/Pi/other-browser performance is untested.
