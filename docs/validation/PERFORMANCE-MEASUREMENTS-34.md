# Measured local workload matrix

Windows/Python3.12.14/Lupa2.8/Lua5.3; actual pure-Lua SHA. Fresh runtimes, serial workload children. Times include generation, validation, hashing and PDF/SVG serialization. Three phases are cold generation, warm generation and validated replay. These are single workload observations on the recorded hardware, not percentile latency or a universal performance guarantee. Lua allocations are snapshots after full collection, not peaks or whole-process memory.

| Workload | Cold s | Warm s | Replay s | Max collected Lua MiB | Instance / scene KiB | PDF / SVG KiB | Actual counts |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| floral-growth-small | 5.181 | 3.861 | 5.003 | 7.44 | 335.7 / 392.5 | 335.5 / 378.5 | `{"growth":{"nodes":12,"roots":1},"legacy":{"chunks":7,"drawing_operations":218}}` |
| floral-growth-medium | 22.768 | 19.506 | 14.706 | 16.67 | 935.5 / 1088.5 | 862.9 / 1000.8 | `{"growth":{"nodes":109,"roots":1},"legacy":{"chunks":20,"drawing_operations":614}}` |
| floral-growth-large | 38.239 | 39.759 | 35.931 | 29.81 | 1962.5 / 2271.8 | 1809.4 / 2050.4 | `{"growth":{"nodes":192,"roots":1},"legacy":{"chunks":34,"drawing_operations":1082}}` |
| knot-topology-small | 0.232 | 0.183 | 0.193 | 2.62 | 10.8 / 5.8 | 5.0 / 7.0 | `{"graph":{"edges":12,"vertices":9},"strands":{"components":3,"crossings":12}}` |
| knot-topology-medium | 1.257 | 1.287 | 1.232 | 4.29 | 33.9 / 17.8 | 14.8 / 21.8 | `{"graph":{"edges":40,"vertices":25},"strands":{"components":5,"crossings":40}}` |
| knot-topology-large | 8.437 | 7.244 | 6.093 | 8.47 | 93.6 / 49.0 | 40.2 / 59.9 | `{"graph":{"edges":112,"vertices":64},"strands":{"components":8,"crossings":112}}` |
| circle-packing-small | 0.736 | 0.461 | 0.520 | 7.90 | 81.3 / 56.1 | 40.1 / 80.4 | `{"circle_packing":{"circles":7,"triangles":6},"graph":{"edges":204,"vertices":234}}` |
| circle-packing-medium | 3.563 | 2.475 | 2.116 | 27.17 | 338.1 / 244.8 | 173.8 / 350.5 | `{"circle_packing":{"circles":19,"triangles":24},"graph":{"edges":888,"vertices":960}}` |
| circle-packing-large | 12.547 | 14.109 | 13.717 | 106.12 | 1393.5 / 1038.7 | 735.5 / 1487.5 | `{"circle_packing":{"circles":61,"triangles":96},"graph":{"edges":3768,"vertices":3924}}` |
| substitution-small | 0.543 | 0.384 | 0.423 | 5.35 | 90.5 / 26.8 | 13.0 / 34.8 | `{"tiling":{"cells":16,"edges":80,"hierarchy":5,"vertices":65}}` |
| substitution-medium | 1.983 | 1.231 | 1.345 | 14.94 | 337.1 / 97.2 | 46.4 / 127.5 | `{"tiling":{"cells":64,"edges":288,"hierarchy":21,"vertices":225}}` |
| substitution-large | 7.757 | 5.540 | 6.041 | 52.92 | 1311.8 / 372.0 | 175.9 / 488.2 | `{"tiling":{"cells":256,"edges":1088,"hierarchy":85,"vertices":833}}` |
| projection-small | 2.081 | 1.189 | 1.337 | 9.93 | 362.4 / 42.6 | 24.1 / 51.6 | `{"tiling":{"cells":112,"edges":251,"vertices":140}}` |
| projection-medium | 3.214 | 1.997 | 2.225 | 17.93 | 649.8 / 101.3 | 56.8 / 123.6 | `{"tiling":{"cells":206,"edges":447,"vertices":242}}` |
| projection-large | 9.225 | 5.295 | 5.627 | 45.55 | 1592.7 / 361.5 | 201.8 / 443.5 | `{"tiling":{"cells":517,"edges":1088,"vertices":572}}` |
| optimization-small | 2.441 | 1.431 | 1.300 | 18.27 | 265.5 / 45.0 | 23.0 / 52.1 | `{"tiling":{"cells":112,"edges":247,"vertices":136}}` |
| optimization-medium | 2.535 | 2.072 | 1.336 | 18.08 | 274.7 / 52.3 | 30.2 / 59.4 | `{"tiling":{"cells":112,"edges":247,"vertices":136}}` |
| optimization-large | 4.835 | 3.795 | 1.324 | 19.09 | 282.2 / 55.7 | 33.4 / 62.5 | `{"tiling":{"cells":112,"edges":247,"vertices":136}}` |
| mosaic-packing-small | 0.181 | 0.126 | 0.160 | 3.16 | 13.5 / 8.4 | 6.3 / 9.2 | `{"field":{"samples":24}}` |
| mosaic-packing-medium | 1.104 | 0.794 | 0.489 | 6.81 | 49.8 / 31.6 | 23.2 / 35.1 | `{"field":{"samples":95}}` |
| mosaic-packing-large | 2.236 | 1.870 | 0.965 | 11.25 | 94.3 / 60.2 | 44.0 / 66.6 | `{"field":{"samples":180}}` |
| text-shaping-small | 6.093 | 4.696 | 4.178 | 30.60 | 193.9 / 124.6 | 131.8 / 90.2 | `{"field":{"samples":169},"micrography":{"graphemes":123,"streamlines":2},"text":{"reading_order":2,"runs":2}}` |
| text-shaping-medium | 7.424 | 6.186 | 5.423 | 39.76 | 287.1 / 156.2 | 258.3 / 257.9 | `{"field":{"samples":169},"micrography":{"graphemes":433,"streamlines":8},"text":{"reading_order":6,"runs":6}}` |
| text-shaping-large | 22.198 | 21.989 | 15.940 | 76.85 | 762.0 / 251.6 | 650.9 / 778.1 | `{"field":{"samples":169},"micrography":{"graphemes":1394,"streamlines":21},"text":{"reading_order":9,"runs":9}}` |
| example-synthesis-small | 0.302 | 0.232 | 0.158 | 3.26 | 27.4 / 4.2 | 4.0 / 3.7 | `{"field":{"samples":13}}` |
| example-synthesis-medium | 0.968 | 0.784 | 0.363 | 5.96 | 110.1 / 9.8 | 9.0 / 8.6 | `{"field":{"samples":37}}` |
| example-synthesis-large | 3.277 | 2.661 | 1.082 | 14.04 | 387.9 / 20.5 | 18.8 / 18.2 | `{"field":{"samples":73}}` |

Each raw receipt includes exact recipe and shared-source fingerprints, budget spending, solver receipts where exposed, output byte sizes and instance/scene hashes. All phases agree byte for byte within each workload. Source/input guards invalidate stale successful results. Rejections and exploratory runs are retained separately.

## Alternating-order before/after repetitions

Three fresh-process pairs compare the exact stage33 core with the stage34 core, alternating order. All instance/scene hashes agree in every pair and phase.

- cold generation: baseline median 3.817s, candidate median 2.791s; observed paired ratios 1.37, 1.14, 1.40.
- warm generation: baseline median 3.873s, candidate median 1.723s; observed paired ratios 2.04, 2.48, 2.38.
- validated replay: baseline median 4.562s, candidate median 1.954s; observed paired ratios 2.33, 2.33, 2.62.

No extrapolation to other families, native TeX or other devices is justified by this periodic comparison.
