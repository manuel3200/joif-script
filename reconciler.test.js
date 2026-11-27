const { test } = require('node:test');
const assert = require('node:assert/strict');
const { reconcileAccounts, purgeExpiredDemos } = require('./account-reconciler');

test('Linux reconciliation locks expired and quota-exhausted accounts, records status only after success and does not create missing users', async () => {
  const writes = [], commands = [];
  const rows = [
    { id: 1, username: 'expired', expiration_date: '2020-01-01', status: 'active', bytes_used: 0, data_limit_bytes: 0 },
    { id: 2, username: 'valid', expiration_date: '2099-01-01', status: 'active', bytes_used: 500, data_limit_bytes: 1000 },
    { id: 3, username: 'missing', expiration_date: '2020-01-01', status: 'active', bytes_used: 0, data_limit_bytes: 0 },
    { id: 4, username: 'root', expiration_date: '2020-01-01', status: 'active', bytes_used: 0, data_limit_bytes: 0 },
    { id: 5, username: 'capped', expiration_date: '2099-01-01', status: 'active', bytes_used: 2048, data_limit_bytes: 1024 }
  ];
  const db = { async query(sql, params) { if (sql.startsWith('SELECT')) return { rows }; writes.push({ sql, params }); } };
  const system = async (cmd, args) => {
    commands.push([cmd, args]);
    if (cmd === 'getent') {
      if (args[1] === 'missing') { const e = Error(); e.exitCode = 2; throw e; }
      return args[1] + ':x:1001:1001::/home/u:/bin/false';
    }
    return '';
  };
  assert.deepEqual(
    await reconcileAccounts(db, system, Date.parse('2026-10-11')),
    { expired: 1, quota_exhausted: 1, missing: 1, errors: 1 }
  );
  assert.equal(writes.length, 2);
  assert.deepEqual(writes[0].params, ['expired', 1]);
  assert.deepEqual(writes[1].params, ['quota_exhausted', 5]);
  assert.ok(commands.some(([cmd, args]) => cmd === 'sudo' && args.includes('usermod')));
  assert.ok(!commands.some(([cmd, args]) => args.includes('useradd') || args.includes('root')));
});

test('failed system revocation leaves DB active for retry', async () => {
  const writes = [];
  const db = { async query(sql) { if (sql.startsWith('SELECT')) return { rows: [{ id: 1, username: 'test', expiration_date: '2020-01-01', status: 'active', bytes_used: 0, data_limit_bytes: 0 }] }; writes.push(sql); } };
  const system = async (cmd) => { if (cmd === 'getent') return 'test:x:1001:1001::/:/bin/false'; throw Error('system denied'); };
  assert.equal((await reconcileAccounts(db, system)).errors, 1);
  assert.equal(writes.length, 0);
});

test('purgeExpiredDemos deletes only demos expired past 24h grace period', async () => {
  const deletedIds = [];
  const now = Date.parse('2026-11-27T12:00:00Z');
  const rows = [
    { id: 10, username: 'demo-old', alias: null, expiration_date: '2026-11-25T10:00:00Z', status: 'expired' },
    { id: 11, username: 'demo-recent', alias: null, expiration_date: '2026-11-27T06:00:00Z', status: 'expired' },
    { id: 12, username: 'cliente1', alias: 'Juan', expiration_date: '2026-11-20T00:00:00Z', status: 'expired' }
  ];
  const db = {
    async query(sql, params) {
      if (sql.startsWith('SELECT')) return { rows };
      if (sql.startsWith('DELETE')) deletedIds.push(params[0]);
    }
  };
  const system = async () => '';
  const summary = await purgeExpiredDemos(db, system, now);
  assert.equal(summary.purged, 1);
  assert.deepEqual(summary.users, ['demo-old']);
  assert.deepEqual(deletedIds, [10]);
});
