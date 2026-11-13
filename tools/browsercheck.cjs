/* Real browser consumer; the page/worker executes the actual shared Lua files. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const args = Object.fromEntries(process.argv.slice(2).map((x, i, all) => x.startsWith('--') ? [x.slice(2), all[i + 1]] : null).filter(Boolean));
const root = path.resolve(__dirname, '..');
const pw = require(args.playwright || 'playwright');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const read = name => JSON.parse(fs.readFileSync(name, 'utf8'));
const write = (name, value) => fs.writeFileSync(name, JSON.stringify(value, null, 2) + '\n');
async function main() {
  if (!args.reference) throw Error('--reference must name a verified native CLI receipt');
  const reference = read(args.reference);
  if (Object.keys(reference.families).length !== 22) throw Error('Native family coverage missing');
  let nativeSources = null;
  if (args['native-sources']) {
    nativeSources = read(args['native-sources']);
    if (nativeSources.source_digest !== reference.source_digest) throw Error('Native reference fingerprint mismatch');
    for (const [name, digest] of Object.entries(nativeSources.files)) {
      if (hash(fs.readFileSync(path.join(root, name))) !== digest) throw Error('Shared native source changed: ' + name);
    }
  }
  const browser = await pw.chromium.launch({headless: true, ...(args.executable ? {executablePath: args.executable} : {})});
  const page = await browser.newPage();
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(args.url || 'http://127.0.0.1:8767/');
    const loaded = await page.evaluate(() => runtimeReady);
    const digest = loaded.manifest.source_digest;
    const output = args.output || path.join(root, 'build/browser-check', digest);
    fs.mkdirSync(output, {recursive: true});
    const catalog = JSON.parse(loaded.bundle.examples['catalog.json']).examples;
    if (catalog.length !== 22) throw Error('Browser catalog does not cover22 families');
    const runtime = {browser: await browser.version(), user_agent: await page.evaluate(() => navigator.userAgent),
      source_digest: digest, source_files: loaded.manifest.source_files, browsercheck_sha256: hash(fs.readFileSync(__filename)),
      native_reference_sha256: hash(fs.readFileSync(args.reference)), native_reference_scope: reference.scope ?? 'Native CLI receipt', native_source_guard: nativeSources?.source_digest ?? 'Unbound development comparison; exact native checkout binding remains a separate gate'};
    write(path.join(output, 'runtime.json'), runtime);
    const completed = {};
    for (const row of catalog) {
      const casePath = path.join(output, row.id + '.json');
      if (args.resume === 'true' && fs.existsSync(casePath)) {
        const cached = read(casePath);
        if (cached.source_digest === digest && cached.status === 'passed' && JSON.stringify(cached.native_expected) === JSON.stringify(reference.families[row.id].artifacts)) { completed[row.id] = cached; continue; }
      }
      console.log('Starting actual browser generation', row.id, new Date().toISOString());
      const generated = await page.evaluate(async row => {
        const loaded = await runtimeReady, started = performance.now();
        const recipe = loaded.bundle.examples[row.recipe];
        window.__generated = await patternClient.execute({command: 'generate', files: {'recipe.json': recipe}});
        return {elapsed_ms: performance.now() - started, manifest: __generated.manifest, stats: __generated.stats};
      }, row);
      const expected = reference.families[row.id];
      if (!expected || expected.family !== row.family) throw Error('Native family metadata mismatch: ' + row.id);
      const manifest = Object.fromEntries(generated.manifest.map(item => [item.name, item]));
      const differences = [];
      for (const [name, sha] of Object.entries(expected.artifacts)) if (manifest[name]?.sha256 !== sha) differences.push(name);
      const report = {source_digest: digest, id: row.id, family: row.family, generated, native_expected: expected.artifacts, differences, status: differences.length ? 'failed' : 'generation_passed_replay_pending'};
      write(casePath, report);
      if (differences.length) {
        const actual = await page.evaluate(() => Object.fromEntries(['instance.json', 'scene.json', 'record.json', 'recipe.json'].filter(name => __generated.assets[name]).map(name => [name, new TextDecoder().decode(__generated.assets[name])])));
        for (const [name, text] of Object.entries(actual)) fs.writeFileSync(path.join(output, row.id + '-' + name), text);
        if (!['micrography', 'decobrush'].includes(row.id)) throw Error('Unapproved native byte differences: ' + row.id + ' ' + differences.join(','));
        const numerical = path.join(output, 'numerical', row.id); fs.mkdirSync(numerical, {recursive:true});
        const binary = await page.evaluate(()=>Object.fromEntries(['instance.json','pattern.pdf','pattern.svg'].map(name=>[name,Array.from(__generated.assets[name])])));
        for (const [name, bytes] of Object.entries(binary)) fs.writeFileSync(path.join(numerical,name),Buffer.from(bytes));
        const native = path.join(args['numerical-reference'] || path.join(path.dirname(args.reference),'numerical'),row.id);
        const comparison = spawnSync(args.python || 'python3', [path.join(__dirname,'browser_parity.py'),'--family',row.id,'--actual',numerical,'--native',native,'--expected',args.reference],{encoding:'utf8',timeout:60000});
        if (comparison.status !== 0) throw Error('Independent native numerical parity failed: '+row.id+' '+comparison.stderr);
        report.numerical_comparison = JSON.parse(comparison.stdout);
      }
      console.log('Starting actual browser instance replay', row.id, new Date().toISOString());
      const replayed = await page.evaluate(async () => {
        const files = Object.create(null), generated = __generated;
        for (const [name, bytes] of Object.entries(generated.assets)) if (['recipe.json', 'instance.json', 'record.json'].includes(name) || /^block-[a-f0-9]{64}\.json$/.test(name)) files[name] = bytes;
        const options = {command: 'replay', files};
        if (generated.assets['instance-format.json']) options.instance_transport = JSON.parse(new TextDecoder().decode(generated.assets['instance-format.json'])).schema;
        const started = performance.now(), result = await patternClient.execute(options);
        window.__generated = null;
        return {elapsed_ms: performance.now() - started, manifest: result.manifest, stats: result.stats};
      });
      const replayManifest = Object.fromEntries(replayed.manifest.map(item => [item.name, item.sha256]));
      for (const [name, sha] of Object.entries(expected.artifacts)) if (replayManifest[name] !== manifest[name].sha256) throw Error('Browser instance roundtrip changed: ' + row.id + '/' + name);
      report.replayed = replayed; report.status = 'passed'; report.comparison = differences.length ? 'Strict structural/binary64-roundoff comparison; own replay exact' : 'Native and own replay byte exact'; completed[row.id] = report; write(casePath, report);
      console.log('Browser/native generation and replay passed', row.id);
    }
    if (Object.values(completed).some(row=>row.status !== 'passed')) throw Error('Diagnostic coverage finished; native byte differences remain unaccepted');
    if (Object.keys(completed).length !== 22 || errors.length) throw Error('Browser coverage/page-error gate failed: ' + errors.join(';'));
    write(path.join(output, 'families.json'), {schema_version: 1, status: 'passed', runtime, families: completed,
      comparison: 'Native byte hashes for20 families; two libm-sensitive families use independently bounded binary64 comparison of instances/SVG/PDF and exact structure/text/resources; all22 own replays byte exact',
      remaining: 'Protocol/cancellation/order/resource/cache/offline adversarial gates require their separate receipt'});
    console.log('Real browser family gate passed22 families:', digest);
  } finally { await browser.close(); }
}
main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
