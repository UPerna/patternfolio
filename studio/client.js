import {sha256, ImmutableResultCache} from './cache.js';
export {ImmutableResultCache};
export const PROTOCOL = 'pattern-browser-v1';
const encoder = new TextEncoder();
const COMMANDS = new Set(['capabilities', 'schema', 'validate', 'generate', 'validate-instance', 'render', 'replay', 'diagnose']);
function failure(code, message) { return Object.assign(new Error(message), {code}); }
function shape(value) {
  const queue = [[value, 0]], seen = new Set(); let count = 0;
  while (queue.length) {
    const [item, depth] = queue.pop();
    if (++count > 100000 || depth > 60) throw failure('budget_exhausted', 'Message object/depth budget exceeded');
    if (!item || typeof item !== 'object' || item instanceof Uint8Array) continue;
    if (seen.has(item)) throw failure('invalid_input', 'Cyclic or aliased message objects');
    seen.add(item);
    if (Object.getPrototypeOf(item) !== Object.prototype && !Array.isArray(item) && Object.getPrototypeOf(item) !== null) throw failure('invalid_input', 'Plain message objects required');
    for (const value of Object.values(item)) queue.push([value, depth + 1]);
  }
}
export class PatternWorkerClient {
  constructor(base = './', options = {}) {
    this.base = new URL(base, location.href); this.generation = 0; this.nextId = 0;
    this.cache = options.cache ?? null; this.options = options;
  }
  async load() {
    if (!this.loading) this.loading = (async () => {
      const response = await fetch(new URL('assets.json', this.base));
      if (!response.ok) throw failure('asset_error', 'Cannot load asset manifest');
      const manifest = await response.json();
      if (manifest.schema_version !== 1 || manifest.protocol !== PROTOCOL) throw failure('asset_error', 'Unsupported asset manifest');
      const files = {};
      for (const name of ['worker.js', 'wasmoon.js', 'sha256.js', 'runtime.wasm', 'bundle.json']) {
        const row = manifest.assets[name];
        if (!row || row.bytes > 8 * 1024 * 1024 || !/^[a-f0-9]{64}$/.test(row.sha256)) throw failure('asset_error', 'Invalid asset descriptor');
        const result = await fetch(new URL(name, this.base));
        if (!result.ok) throw failure('asset_error', 'Cannot load ' + name);
        const bytes = new Uint8Array(await result.arrayBuffer());
        if (bytes.length !== row.bytes || await sha256(bytes) !== row.sha256) throw failure('asset_error', 'Asset digest mismatch: ' + name);
        files[name] = bytes;
      }
      const decoder = new TextDecoder('utf-8', {fatal: true});
      const bundle = JSON.parse(decoder.decode(files['bundle.json']));
      for (const [name, text] of Object.entries(bundle.source)) {
        if (await sha256(encoder.encode(text)) !== manifest.source_files[name]) throw failure('asset_error', 'Source digest mismatch');
      }
      return {manifest, bundle, worker: decoder.decode(files['worker.js']), vendor: decoder.decode(files['wasmoon.js']), hash: decoder.decode(files['sha256.js']), wasm: files['runtime.wasm']};
    })();
    return this.loading;
  }
  cancel(code = 'cancelled') {
    const job = this.pending;
    if (!job) return false;
    this.finish(job, failure(code, code === 'superseded' ? 'Replaced by a newer generation' : 'Generation cancelled'));
    return true;
  }
  finish(job, error, value) {
    if (this.pending !== job) return;
    clearTimeout(job.timer); job.worker?.terminate();
    if (job.url) URL.revokeObjectURL(job.url);
    this.pending = null;
    if (error) job.reject(error); else job.resolve(value);
  }
  execute(options, controls = {}) {
    this.cancel('superseded');
    const generation = ++this.generation, request_id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const job = {generation, request_id, resolve, reject, assets: Object.create(null), manifest: null, received: Object.create(null)};
      this.pending = job;
      (async () => {
        shape(options); shape(controls);
        const allowed = new Set(['command', 'family', 'formats', 'limits', 'dependencies', 'instance_transport', 'previous_recipe', 'edits', 'files']);
        if (!options || Object.keys(options).some(key => !allowed.has(key)) || !COMMANDS.has(options.command)) throw failure('invalid_input', 'Unsupported browser request');
        const instruction_limit = controls.instructionLimit ?? 16000000000;
        const watchdog = controls.watchdogMs ?? 300000;
        const memory_limit = controls.memoryLimitBytes ?? 256 * 1024 * 1024;
        if (!Number.isSafeInteger(instruction_limit) || instruction_limit < 1000 || instruction_limit > 32000000000 ||
            !Number.isSafeInteger(watchdog) || watchdog < 1 || watchdog > 300000 ||
            !Number.isSafeInteger(memory_limit) || memory_limit < 2 * 1024 * 1024 || memory_limit > 256 * 1024 * 1024) throw failure('invalid_input', 'Invalid execution bound');
        const request = {schema_version: 1, command: options.command, input_files: []}, files = [];
        for (const name of ['family', 'formats', 'limits', 'dependencies', 'instance_transport', 'previous_recipe', 'edits']) if (options[name] !== undefined) request[name] = options[name];
        let total = 0;
        for (const [name, value] of Object.entries(options.files ?? {})) {
          if (!/^[A-Za-z0-9_.-]{1,160}$/.test(name)) throw failure('invalid_input', 'Input filename is not admitted');
          const bytes = typeof value === 'string' ? encoder.encode(value) : value instanceof Uint8Array ? value.slice() : null;
          if (!bytes) throw failure('invalid_input', 'File contents must be text or bytes');
          total += bytes.length;
          if (total > 32 * 1024 * 1024 || files.length >= 1024) throw failure('budget_exhausted', 'Input byte/file budget');
          files.push({name, data: bytes.buffer});
          request.input_files.push({name, bytes: bytes.length, sha256: await sha256(bytes)});
        }
        if (encoder.encode(JSON.stringify(request)).length > 2 * 1024 * 1024) throw failure('budget_exhausted', 'Request header too large');
        const loaded = await this.load();
        if (this.pending !== job) return;
        job.url = URL.createObjectURL(new Blob([loaded.worker], {type: 'text/javascript'}));
        const worker = job.worker = new Worker(job.url);
        job.timer = setTimeout(() => this.finish(job, failure('timeout', 'Browser watchdog aborted; no result was accepted')), watchdog);
        worker.onerror = event => this.finish(job, failure('worker_error', event.message));
        worker.onmessage = async event => {
          if (this.pending !== job || job.worker !== worker) return;
          const message = event.data;
          if (message?.request_id !== request_id || message.generation !== generation) return;
          try {
            if (message.schema_version !== 1) throw failure('invalid_response', 'Unsupported response version');
            if (message.type === 'ready') {
              worker.postMessage({schema_version: 1, type: 'execute', generation, request_id, request, files, instruction_limit}, files.map(x => x.data));
            } else if (message.type === 'progress') {
              controls.progress?.({generation, request_id, phase: message.phase, instructions: message.instructions, lua_memory_bytes: message.lua_memory_bytes});
            } else if (message.type === 'error') {
              this.finish(job, Object.assign(failure(message.error?.code ?? 'worker_error', message.error?.message ?? 'Worker failure'), {stats: message.stats}));
            } else if (message.type === 'assets') {
              if (job.manifest || !Array.isArray(message.assets) || message.assets.length < 1 || message.assets.length > 1024) throw failure('invalid_response', 'Invalid output metadata');
              let total = 0; const seen = new Set();
              for (const row of message.assets) {
                if (!/^[A-Za-z0-9_.-]{1,160}$/.test(row.name) || seen.has(row.name) || !Number.isSafeInteger(row.bytes) || row.bytes < 0 || !/^[a-f0-9]{64}$/.test(row.sha256)) throw failure('invalid_response', 'Invalid output descriptor');
                total += row.bytes; if (total > 64 * 1024 * 1024) throw failure('budget_exhausted', 'Output byte budget');
                seen.add(row.name); job.assets[row.name] = new Uint8Array(row.bytes); job.received[row.name] = 0;
              }
              job.manifest = message.assets;
            } else if (message.type === 'asset-chunk') {
              const bytes = job.assets[message.name];
              if (!bytes || message.offset !== job.received[message.name] || !(message.data instanceof ArrayBuffer) || message.data.byteLength > 262144 || message.offset + message.data.byteLength > bytes.length) throw failure('invalid_response', 'Invalid asset chunk');
              bytes.set(new Uint8Array(message.data), message.offset); job.received[message.name] += message.data.byteLength;
            } else if (message.type === 'complete') {
              if (!job.manifest) throw failure('invalid_response', 'Missing output manifest');
              if (!Number.isSafeInteger(message.instructions) || message.instructions < 0 || message.instructions > instruction_limit ||
                  !Number.isSafeInteger(message.lua_memory_bytes) || message.lua_memory_bytes < 1 || message.lua_memory_bytes > memory_limit) throw failure('invalid_response', 'Invalid resource evidence');
              for (const row of job.manifest) if (job.received[row.name] !== row.bytes || await sha256(job.assets[row.name]) !== row.sha256) throw failure('invalid_response', 'Incomplete or damaged output');
              if (this.pending !== job) return;
              const value = {schema_version: 1, generation, request_id, manifest: job.manifest, assets: job.assets,
                source_digest: loaded.manifest.source_digest, stats: {instructions: message.instructions, lua_memory_bytes: message.lua_memory_bytes, profile: message.profile, host_identity: message.host_identity, host_digest: message.host_digest}};
              value.cache_key = await sha256(encoder.encode(loaded.manifest.source_digest + '\n' + JSON.stringify(job.manifest)));
              if (this.cache) await this.cache.put(value.cache_key, value);
              this.finish(job, null, value);
            } else throw failure('invalid_response', 'Unknown worker response');
          } catch (error) { this.finish(job, error); }
        };
        worker.postMessage({schema_version: 1, type: 'init', generation, request_id, bundle: loaded.bundle,
          vendor: loaded.vendor, hash: loaded.hash, wasm: loaded.wasm, instruction_limit, watchdog_ms: watchdog, memory_limit});
      })().catch(error => this.finish(job, error));
    });
  }
}
