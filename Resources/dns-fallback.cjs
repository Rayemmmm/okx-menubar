'use strict';
// Per-process fallback only. HTTPS certificates remain fully verified.
// Only public hostnames are sent to the resolver; no API credentials or URLs.
const dns = require('node:dns');
const https = require('node:https');
const originalLookup = dns.lookup.bind(dns);
const allowed = new Set([
  'registry.npmjs.org', 'www.okx.com', 'eea.okx.com',
  'us.okx.com', 'tr.okx.com',
]);
const cache = new Map();
const pending = new Map();

function resolvePublicHost(hostname) {
  const old = cache.get(hostname);
  if (old && old.expires > Date.now()) return Promise.resolve(old.addresses);
  if (pending.has(hostname)) return pending.get(hostname);
  const promise = new Promise((resolve, reject) => {
    const req = https.get({
      hostname: '1.1.1.1', port: 443,
      path: '/dns-query?name=' + encodeURIComponent(hostname) + '&type=A',
      headers: { accept: 'application/dns-json' }, timeout: 8000,
    }, (res) => {
      let body = '';
      res.on('data', chunk => {
        body += chunk;
        if (body.length > 65536) res.destroy(new Error('DNS response too large'));
      });
      res.on('error', reject);
      res.on('end', () => {
        try {
          if (res.statusCode !== 200) throw new Error('DNS unavailable');
          const data = JSON.parse(body);
          const answers = (data.Answer || []).filter(a => a.type === 1 && /^\d+\.\d+\.\d+\.\d+$/.test(a.data));
          if (data.Status !== 0 || !answers.length) throw new Error('DNS unavailable');
          const addresses = answers.map(a => ({ address: a.data, family: 4 }));
          const ttl = Math.max(1, Math.min(300, ...answers.map(a => Number(a.TTL) || 30)));
          cache.set(hostname, { addresses, expires: Date.now() + ttl * 1000 });
          resolve(addresses);
        } catch (error) { reject(error); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('DNS timeout')));
    req.on('error', reject);
  }).finally(() => pending.delete(hostname));
  pending.set(hostname, promise);
  return promise;
}

dns.lookup = function lookup(hostname, options, callback) {
  if (typeof options === 'function') { callback = options; options = {}; }
  if (typeof options === 'number') options = { family: options };
  options = options || {};
  return originalLookup(hostname, options, (error, address, family) => {
    if (!error || !allowed.has(hostname) || options.family === 6 || options.family === 'IPv6') {
      return callback(error, address, family);
    }
    resolvePublicHost(hostname).then(addresses => {
      if (options.all) callback(null, addresses);
      else callback(null, addresses[0].address, 4);
    }, () => callback(error));
  });
};
