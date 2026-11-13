# Measured local workload matrix

Windows/Python3.12.14/Lupa2.8/Lua5.3; actual pure-Lua SHA. Fresh runtimes, serial workload children. Times include generation, validation, hashing and PDF/SVG serialization. Three phases are cold generation, warm generation and validated replay. These are single workload observations on the recorded hardware, not percentile latency or a universal performance guarantee. Lua allocations are snapshots after full collection, not peaks or whole-process memory.

| Workload | Cold s | Warm s | Replay s | Max collected Lua MiB | Instance / scene KiB | PDF / SVG KiB | Actual counts |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| floral-growth-small | 4.893 | 3.376 | 3.115 | 7.44 | 335.7 / 392.5 | 335.5 / 378.5 | `{"growth":{"nodes":12,"roots":1},"legacy":{"chunks":7,"drawing_operations":218}}` |
| floral-growth-medium | 14.551 | 13.414 | 13.327 | 16.91 | 935.5 / 1088.5 | 862.9 / 1000.8 | `{"growth":{"nodes":109,"roots":1},"legacy":{"chunks":20,"drawing_operations":614}}` |
| floral-growth-large | 37.247 | 37.329 | 37.680 | 29.87 | 1962.5 / 2271.8 | 1809.4 / 2050.4 | `{"growth":{"nodes":192,"roots":1},"legacy":{"chunks":34,"drawing_operations":1082}}` |
| knot-topology-small | 0.237 | 0.203 | 0.208 | 2.60 | 10.8 / 5.8 | 5.0 / 7.0 | `{"graph":{"edges":12,"vertices":9},"strands":{"components":3,"crossings":12}}` |
| knot-topology-medium | 1.231 | 1.115 | 0.898 | 4.30 | 33.9 / 17.8 | 14.8 / 21.8 | `{"graph":{"edges":40,"vertices":25},"strands":{"components":5,"crossings":40}}` |
| knot-topology-large | 7.745 | 7.324 | 5.329 | 8.48 | 93.6 / 49.0 | 40.2 / 59.9 | `{"graph":{"edges":112,"vertices":64},"strands":{"components":8,"crossings":112}}` |
| circle-packing-small | 0.758 | 0.579 | 0.533 | 7.90 | 81.3 / 56.1 | 40.1 / 80.4 | `{"circle_packing":{"circles":7,"triangles":6},"graph":{"edges":204,"vertices":234}}` |
| circle-packing-medium | 2.947 | 2.066 | 2.147 | 27.13 | 338.1 / 244.8 | 173.8 / 350.5 | `{"circle_packing":{"circles":19,"triangles":24},"graph":{"edges":888,"vertices":960}}` |
| circle-packing-large | 14.636 | 13.599 | 13.056 | 107.13 | 1393.5 / 1038.7 | 735.5 / 1487.5 | `{"circle_packing":{"circles":61,"triangles":96},"graph":{"edges":3768,"vertices":3924}}` |
| substitution-small | 0.584 | 0.360 | 0.421 | 5.35 | 90.5 / 26.8 | 13.0 / 34.8 | `{"tiling":{"cells":16,"edges":80,"hierarchy":5,"vertices":65}}` |
| substitution-medium | 1.997 | 1.253 | 1.362 | 14.94 | 337.1 / 97.2 | 46.4 / 127.5 | `{"tiling":{"cells":64,"edges":288,"hierarchy":21,"vertices":225}}` |
| substitution-large | 7.653 | 5.723 | 5.108 | 52.51 | 1311.8 / 372.0 | 175.9 / 488.2 | `{"tiling":{"cells":256,"edges":1088,"hierarchy":85,"vertices":833}}` |
| projection-small | 1.964 | 1.136 | 1.231 | 9.93 | 362.4 / 42.6 | 24.1 / 51.6 | `{"tiling":{"cells":112,"edges":251,"vertices":140}}` |
| projection-medium | 3.451 | 2.208 | 2.409 | 17.84 | 649.8 / 101.3 | 56.8 / 123.6 | `{"tiling":{"cells":206,"edges":447,"vertices":242}}` |
| projection-large | 10.312 | 6.154 | 6.077 | 45.55 | 1592.7 / 361.5 | 201.8 / 443.5 | `{"tiling":{"cells":517,"edges":1088,"vertices":572}}` |
| optimization-small | 1.914 | 1.431 | 1.406 | 18.46 | 265.5 / 45.0 | 23.0 / 52.1 | `{"tiling":{"cells":112,"edges":247,"vertices":136}}` |
| optimization-medium | 2.724 | 2.023 | 1.290 | 18.01 | 274.7 / 52.3 | 30.2 / 59.4 | `{"tiling":{"cells":112,"edges":247,"vertices":136}}` |
| optimization-large | 5.075 | 4.550 | 1.422 | 18.48 | 282.2 / 55.7 | 33.4 / 62.5 | `{"tiling":{"cells":112,"edges":247,"vertices":136}}` |
| mosaic-packing-small | 0.246 | 0.156 | 0.173 | 3.16 | 13.5 / 8.4 | 6.3 / 9.2 | `{"field":{"samples":24}}` |
| mosaic-packing-medium | 0.866 | 0.646 | 0.453 | 6.76 | 49.8 / 31.6 | 23.2 / 35.1 | `{"field":{"samples":95}}` |
| mosaic-packing-large | 2.289 | 1.949 | 1.055 | 11.24 | 94.3 / 60.2 | 44.0 / 66.6 | `{"field":{"samples":180}}` |
| text-shaping-small | 5.501 | 4.892 | 4.144 | 30.61 | 193.9 / 124.6 | 131.8 / 90.2 | `{"field":{"samples":169},"micrography":{"graphemes":123,"streamlines":2},"text":{"reading_order":2,"runs":2}}` |
| text-shaping-medium | 7.883 | 5.854 | 4.856 | 39.46 | 287.1 / 156.2 | 258.3 / 257.9 | `{"field":{"samples":169},"micrography":{"graphemes":433,"streamlines":8},"text":{"reading_order":6,"runs":6}}` |
| text-shaping-large | 22.309 | 20.739 | 13.470 | 76.85 | 762.0 / 251.6 | 650.9 / 778.1 | `{"field":{"samples":169},"micrography":{"graphemes":1394,"streamlines":21},"text":{"reading_order":9,"runs":9}}` |
| example-synthesis-small | 0.363 | 0.220 | 0.163 | 3.26 | 27.4 / 4.2 | 4.0 / 3.7 | `{"field":{"samples":13}}` |
| example-synthesis-medium | 1.212 | 0.981 | 0.462 | 5.96 | 110.1 / 9.8 | 9.0 / 8.6 | `{"field":{"samples":37}}` |
| example-synthesis-large | 3.271 | 2.670 | 1.381 | 14.04 | 387.9 / 20.5 | 18.8 / 18.2 | `{"field":{"samples":73}}` |

Each raw receipt includes exact recipe and shared-source fingerprints, budget spending, solver receipts where exposed, output byte sizes and instance/scene hashes. All phases agree byte for byte within each workload. Source/input guards invalidate stale successful results. Rejections and exploratory runs are retained separately.

## Alternating-order before/after repetitions

Three fresh-process pairs compare the exact stage33 core with the stage34 core, alternating order. All instance/scene hashes agree in every pair and phase.

- cold generation: baseline median 4.035s, candidate median 2.762s; observed paired ratios 1.60, 1.42, 1.31.
- warm generation: baseline median 4.213s, candidate median 1.701s; observed paired ratios 2.29, 2.73, 2.61.
- validated replay: baseline median 5.454s, candidate median 1.761s; observed paired ratios 2.55, 3.25, 2.41.

No extrapolation to other families, native TeX or other devices is justified by this periodic comparison.
