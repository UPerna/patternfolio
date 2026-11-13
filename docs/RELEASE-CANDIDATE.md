# Build and verify a release candidate

Start with a frozen Git revision and the [quickstart](QUICKSTART.md). The dependency and action records are in `DEPENDENCIES.lock.json` at the source root. Current CI uses exact action commits, a digest-pinned native image and an explicit PR head checkout. It has read-only repository permissions and does not persist checkout credentials.

After the normal native export and atlas builds, assemble the candidate:

```sh
python3 tools/release_candidate.py --atlas build/pattern-atlas --output build/release-candidate
```

Use a new output directory. The folder contains `florilegium-source.zip`, `florilegium-browser.zip`, `florilegium-atlas.zip`, `release.json` and `SHA256SUMS`. `release.json` names the exact source revision/tree and each component digest. The source ZIP preserves the declared source selection's canonical Git bytes and modes. It includes a `SOURCE.json` file map and a checksum list. Legacy source-kit previews remain subject to their existing comparison policy; they cannot change this canonical release source.

Verify the checksums before extraction. Extract the source ZIP into a fresh directory, then run the source-only verification with the declared TeX Live and QA dependencies:

```sh
python3 tools/release_sourcecheck.py --output "../Clean source verification"
```

That check generates and replays all 22 CLI profiles, exercises both real TeX adapters, rebuilds the browser from packaged files, and reassembles the canonical source ZIP without Git. It saves native logs, receipts, the source digest and the comparison result. Native test paths contain spaces, and the CLI also checks a Unicode output path. This is separate from the Windows Lupa development host's source-path limitation.

For the runnable browser component:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory florilegium-browser
```

Open `http://127.0.0.1:8000/` after extracting the browser ZIP. Serve the atlas on another port or open its `index.html`. Keep each folder's notices and checksums beside the files. Complete atlas profile folders include every replay artifact, including spatial networks and any legacy blocks.

Repeated component archives are byte-identical for the same frozen source and Python/zlib archive profile. The release manifest records that profile. Across archive-library versions, compare extracted file bytes and modes. Same-runtime instance/scene/vector replay is byte exact. Full TeX documents use the documented path, text, placement and render comparisons, while named native/browser numerical comparisons retain independent structural checks.

The compact release source includes all selected JSON evidence receipts. Historical raw logs and the complete Git story remain in the canonical Git archive, full-history bundle and execution checkpoint. No credentials, local caches, private reference papers or optional external solver installation belong in the components.

CI uploads a review candidate artifact. This process does not merge a branch, deploy a production site or create a public release tag.
