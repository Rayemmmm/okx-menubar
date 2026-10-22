'use strict';
// A fixed, read-only invocation of the pinned official OKX MCP package.
// Credentials are read by that package from ~/.okx/config.toml only.
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const privateSafeStderr = process.stderr.write.bind(process.stderr);
// The upstream TOML parser may include a credential line in a startup error.
// Keep all upstream stderr out of Codex logs; structured MCP errors still work.
process.stderr.write = (_chunk, encoding, callback) => {
  if (typeof encoding === 'function') encoding();
  else if (typeof callback === 'function') callback();
  return true;
};
for (const key of Object.keys(process.env)) {
  if (key.startsWith('OKX_') || ['NODE_DEBUG', 'DEBUG', 'NODE_OPTIONS'].includes(key)) {
    delete process.env[key];
  }
}
require('./dns-fallback.cjs');
const entry = path.join(__dirname, 'runtime/node_modules/@okx_ai/okx-trade-mcp/dist/index.js');
process.argv = [process.execPath, entry, '--profile', 'codex-readonly',
  '--modules', 'market,account,swap', '--read-only', '--no-log', '--live'];
import(pathToFileURL(entry).href).catch(() => {
  privateSafeStderr('OKX read-only server failed to start. No credentials were printed.\n');
  process.exitCode = 1;
});
