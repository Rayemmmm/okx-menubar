// Menu-bar data source. Official OKX MCP only; no credential inspection or logs.
import { Client } from './runtime/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from './runtime/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';
import { lstatSync } from 'node:fs';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
const instrument = 'BTC-USDT-SWAP';
const now = Date.now();
const dayStart = Math.floor((now + 8 * 3600000) / 86400000) * 86400000 - 8 * 3600000;
const allow = new Set(['system_get_capabilities', 'account_get_config', 'account_get_balance_all',
  'swap_get_positions', 'market_get_ticker', 'market_get_mark_price', 'market_get_instruments',
  'swap_get_orders', 'swap_get_algo_orders', 'account_get_bills']);
const client = new Client({ name: 'okx-readonly-menubar', version: '1.0.0' });
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [fileURLToPath(new URL('./launch.cjs', import.meta.url))], stderr: 'pipe',
});
transport.stderr?.on('data', () => {});
const numeric = v => v !== '' && v !== undefined && v !== null && Number.isFinite(Number(v)) ? Number(v) : null;
const sum = values => values.some(v => v === null) ? null : values.reduce((a,b) => a+b, 0);
async function stop() { await client.close().catch(() => {}); }
process.once('SIGTERM', async () => { await stop(); process.exit(1); });
process.once('SIGINT', async () => { await stop(); process.exit(1); });

function privateReady() {
  try {
    const dir = lstatSync(homedir() + '/.okx');
    const file = lstatSync(homedir() + '/.okx/config.toml');
    return dir.isDirectory() && dir.uid === process.getuid() && (dir.mode & 0o777) === 0o700
      && file.isFile() && file.uid === process.getuid() && (file.mode & 0o777) === 0o600;
  } catch { return false; }
}
async function read(name, args = {}) {
  if (!allow.has(name)) throw new Error('Restricted tool');
  const r = await client.callTool({ name, arguments: args }, undefined, { timeout: 15000 });
  const p = r.structuredContent || JSON.parse(r.content.find(c => c.type === 'text').text);
  if (r.isError || p.ok !== true) throw new Error('Read query failed');
  return { data: p.data?.data ?? p.data, requestTime: p.data?.requestTime || p.timestamp };
}
async function pages(name, args, field) {
  let after; const rows = []; const ids = new Set();
  for (let page = 0; page < 10; page++) {
    const r = await read(name, { ...args, limit: 100, ...(after ? { after } : {}) });
    if (!Array.isArray(r.data)) throw new Error('Invalid response');
    for (const item of r.data) {
      const id = item[field];
      if (!id || !ids.has(id)) { rows.push(item); if (id) ids.add(id); }
    }
    if (r.data.length < 100) return rows;
    const next = r.data.at(-1)?.[field];
    if (!next || next === after) throw new Error('Incomplete pagination');
    after = next;
  }
  throw new Error('Incomplete pagination');
}
function fresh(row) {
  const ts = numeric(row?.ts);
  if (ts === null) return false;
  const age = Date.now() - ts;
  return age >= -5000 && age <= 30000;
}
function packAlgo(a, source) {
  return { id: a.algoId || a.attachAlgoId || '', source,
    kind: a.ordType || 'attached', side: a.side || '', size: numeric(a.sz),
    closeFraction: numeric(a.closeFraction),
    tp: numeric(a.tpTriggerPx), sl: numeric(a.slTriggerPx),
    tpType: a.tpTriggerPxType || '', slType: a.slTriggerPxType || '',
    tpOrderPrice: a.tpOrdPx || '', slOrderPrice: a.slOrdPx || '',
    callbackRatio: numeric(a.callbackRatio), callbackSpread: numeric(a.callbackSpread),
    activationPrice: numeric(a.activePx), reduceOnly: a.reduceOnly === true || a.reduceOnly === 'true' };
}
try {
  if (!privateReady()) throw new Error('Private setup unavailable');
  await client.connect(transport);
  const inventory = await client.listTools();
  if (inventory.tools.some(t => t.annotations?.readOnlyHint !== true)) throw new Error('Unsafe inventory');
  for (const name of allow) if (!inventory.tools.some(t => t.name === name)) throw new Error('Missing read tool');
  const capabilities = (await read('system_get_capabilities')).data.capabilities;
  if (capabilities.readOnly !== true || !capabilities.hasAuth || capabilities.demo !== false) throw new Error('Unsafe mode');
  const config = await read('account_get_config');
  if (config.data?.[0]?.perm !== 'read_only') throw new Error('API Read permission not verified');
  const [balance, positions, ticker, mark, contract, orders, conditional, oco, trailing, bills] = await Promise.all([
    read('account_get_balance_all', { accounts: 'trading,funding', showValuation: true,
      valuationCcy: 'USDT', preferParallel: true }),
    read('swap_get_positions', { instType: 'SWAP', instId: instrument }),
    read('market_get_ticker', { instId: instrument }),
    read('market_get_mark_price', { instType: 'SWAP', instId: instrument }),
    read('market_get_instruments', { instType: 'SWAP', instId: instrument }),
    pages('swap_get_orders', { status: 'open', instType: 'SWAP', instId: instrument }, 'ordId'),
    pages('swap_get_algo_orders', { status: 'pending', instType: 'SWAP', instId: instrument, ordType: 'conditional' }, 'algoId'),
    pages('swap_get_algo_orders', { status: 'pending', instType: 'SWAP', instId: instrument, ordType: 'oco' }, 'algoId'),
    pages('swap_get_algo_orders', { status: 'pending', instType: 'SWAP', instId: instrument, ordType: 'move_order_stop' }, 'algoId'),
    pages('account_get_bills', { instType: 'SWAP', ccy: 'USDT', begin: String(dayStart), end: String(now) }, 'billId'),
  ]);
  const allBalance = balance.data;
  const valuation = allBalance.valuation?.details?.[0];
  if (allBalance.trading?.available !== true || allBalance.funding?.available !== true
      || allBalance.valuation?.available !== true || allBalance.valuation?.valuationCcy !== 'USDT'
      || numeric(valuation?.totalBal) === null) throw new Error('Total asset balance unavailable');
  const tick = ticker.data?.[0], markRow = mark.data?.[0];
  if (!fresh(tick) || !fresh(markRow) || !fresh(valuation)) {
    console.log(JSON.stringify({ status: 'stale', fetchedAt: new Date().toISOString(), message: '行情时间戳缺失或超过 30 秒，未显示旧数值。' }));
  } else {
    if (!Array.isArray(positions.data) || positions.data.some(p => numeric(p.pos) === null)) throw new Error('Position quantity missing');
    const spec = contract.data?.[0];
    const active = positions.data.filter(p => Number(p.pos) !== 0);
    const detail = allBalance.trading.details?.find(d => d.ccy === 'USDT');
    const algos = []; const algoIds = new Set();
    for (const a of [...conditional, ...oco, ...trailing]) {
      if (a.algoId && algoIds.has(a.algoId)) continue;
      if (a.algoId) algoIds.add(a.algoId);
      algos.push(packAlgo(a, 'active'));
    }
    for (const p of active) for (const a of p.closeOrderAlgo || []) {
      if (a.algoId && algoIds.has(a.algoId)) continue;
      if (a.algoId) algoIds.add(a.algoId);
      algos.push(packAlgo(a, 'position'));
    }
    const attached = orders.flatMap(o => (o.attachAlgoOrds || []).map(a => packAlgo(a, 'pending-parent')));
    const realizedTypes = new Set(['2','3','5','7','8','9','10']);
    const today = bills.filter(b => realizedTypes.has(b.type) && Number(b.ts) >= dayStart && Number(b.ts) <= now);
    const output = { status: 'ok', fetchedAt: new Date().toISOString(), instrument,
      tickerTime: new Date(Number(tick.ts)).toISOString(), markTime: new Date(Number(markRow.ts)).toISOString(),
      valuationTime: new Date(Number(valuation.ts)).toISOString(),
      totalAssetsUSDT: numeric(valuation.totalBal),
      totalBalanceSource: 'OKX asset valuation totalBal (USDT)',
      fundingValuationUSDT: numeric(valuation.details?.funding),
      earnValuationUSDT: numeric(valuation.details?.earn),
      last: numeric(tick.last), mark: numeric(markRow.markPx),
      equityUSD: numeric(allBalance.trading.totalEq), equityUSDT: numeric(detail?.eq),
      cashUSDT: numeric(detail?.cashBal), availableUSDT: numeric(detail?.availBal),
      floatingUSDT: sum(active.map(p => numeric(p.upl))),
      todayLedgerUSDT: sum(today.map(b => numeric(b.balChg))),
      todayStart: new Date(dayStart).toISOString(), todayBillCount: today.length,
      positions: active.map(p => ({
        direction: p.posSide === 'net' ? (Number(p.pos) > 0 ? '多' : '空') : p.posSide === 'long' ? '多' : p.posSide === 'short' ? '空' : '未知',
        contracts: Math.abs(Number(p.pos)),
        btc: spec?.ctValCcy === 'BTC' && numeric(spec.ctVal) !== null
          ? Math.abs(Number(p.pos)) * Number(spec.ctVal) * (numeric(spec.ctMult) ?? 1) : null,
        entry: numeric(p.avgPx), leverage: numeric(p.lever), marginMode: p.mgnMode,
        floating: numeric(p.upl), ratio: numeric(p.uplRatio), liquidation: numeric(p.liqPx),
        realized: numeric(p.realizedPnl), positionTimestamp: p.uTime || null,
      })),
      ordinaryOrderCount: orders.length, algos, attached,
      readOnly: true, demo: false,
      queryScope: '仅 BTC 永续普通委托、条件/OCO/移动止损及附带止盈止损；其他计划开仓单未覆盖。',
    };
    console.log(JSON.stringify(output));
  }
} catch {
  console.log(JSON.stringify({ status: 'error', fetchedAt: new Date().toISOString(),
    message: '只读查询未完成或权限校验未通过，未显示旧数值。' }));
} finally { await stop(); }
