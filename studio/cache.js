export async function sha256(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(x => x.toString(16).padStart(2, '0')).join('');
}
export class ImmutableResultCache {
  constructor(name = 'florilegium-browser-v1') { this.name = name; }
  async open() {
    if (this.database) return this.database;
    if (!this.opening) this.opening = new Promise((resolve, reject) => {
      const request = indexedDB.open(this.name, 1);
      request.onupgradeneeded = () => request.result.createObjectStore('results');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    try { this.database = await this.opening; }
    catch (error) { this.opening = null; throw error; }
    return this.database;
  }
  async validate(value) {
    if (!value || value.schema_version !== 1 || !Array.isArray(value.manifest) || value.manifest.length < 1 || value.manifest.length > 1024) throw Error('Invalid cache record');
    let size = 0; const seen = new Set();
    for (const row of value.manifest) {
      const bytes = value.assets[row.name];
      if (seen.has(row.name) || !(bytes instanceof Uint8Array) || bytes.length !== row.bytes ||
          !/^[a-f0-9]{64}$/.test(row.sha256) || await sha256(bytes) !== row.sha256) throw Error('Damaged cached asset');
      seen.add(row.name); size += bytes.length;
      if (size > 64 * 1024 * 1024) throw Error('Cache byte budget');
    }
    if (Object.keys(value.assets).length !== seen.size) throw Error('Undeclared cached asset');
    if (value.source_digest !== undefined && !/^[a-f0-9]{64}$/.test(value.source_digest)) throw Error('Invalid cached source digest');
    if (value.cache_key !== undefined) {
      const key = await sha256(new TextEncoder().encode(value.source_digest + '\n' + JSON.stringify(value.manifest)));
      if (key !== value.cache_key) throw Error('Cache identity mismatch');
    }
    return sha256(new TextEncoder().encode(JSON.stringify({manifest: value.manifest, source_digest: value.source_digest ?? null, cache_key: value.cache_key ?? null})));
  }
  async put(key, value) {
    // Capture caller-owned buffers/metadata before any asynchronous digest yields.
    value = structuredClone(value);
    if (value.cache_key !== undefined && key !== value.cache_key) throw Error('Cache key mismatch');
    const digest = await this.validate(value), database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction('results', 'readwrite'), store = transaction.objectStore('results');
      let reused = false, conflict;
      const request = store.get(key);
      request.onsuccess = () => {
        const old = request.result;
        if (old && old.digest !== digest) { conflict = Error('Immutable cache key conflict'); transaction.abort(); return; }
        if (old) reused = true;
        else store.add({digest, value}, key);
      };
      transaction.oncomplete = () => resolve({digest, reused});
      transaction.onabort = transaction.onerror = () => reject(conflict || transaction.error || Error('Cache transaction failed'));
    });
  }
  async get(key) {
    const database = await this.open();
    const record = await new Promise((resolve, reject) => {
      const transaction = database.transaction('results', 'readonly'), request = transaction.objectStore('results').get(key);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    if (!record) return null;
    if (record.value.cache_key !== undefined && record.value.cache_key !== key) throw Error('Cache key mismatch');
    if (await this.validate(record.value) !== record.digest) throw Error('Damaged cache manifest');
    return record.value;
  }
  close() { this.database?.close(); this.database = null; this.opening = null; }
}
