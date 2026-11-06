const { test } = require('node:test');
const assert = require('node:assert/strict');
const { reconcileAccounts } = require('./account-reconciler');
test('Linux reconciliation locks expired accounts, records status only after success and does not create missing users', async () => {
  const writes = [], commands = [];
  const rows = [
    { id: 1, username: 'expired', expiration_date: '2020-01-01', status: 'active' },
    { id: 2, username: 'valid', expiration_date: '2099-01-01', status: 'active' },
    { id: 3, username: 'missing', expiration_date: '2020-01-01', status: 'active' },
    { id: 4, username: 'root', expiration_date: '2020-01-01', status: 'active' }
  ];
  const db = { async query(sql, params) { if (sql.startsWith('SELECT')) return { rows }; writes.push({sql,params}); } };
  const system = async (cmd,args) => { commands.push([cmd,args]); if (cmd === 'getent') { if(args[1] === 'missing') { const e=Error();e.exitCode=2;throw e; } return args[1]+':x:1001:1001::/home/u:/bin/false'; } return ''; };
  assert.deepEqual(await reconcileAccounts(db, system, Date.parse('2026-10-11')), { expired: 1, missing: 1, errors: 1 });
  assert.equal(writes.length, 1); assert.deepEqual(writes[0].params, [1]);
  assert.ok(commands.some(([cmd,args]) => cmd === 'sudo' && args.includes('usermod')));
  assert.ok(!commands.some(([cmd,args]) => args.includes('useradd') || args.includes('root')));
});
test('failed system revocation leaves DB active for retry', async () => {
  const writes=[]; const db={async query(sql,params){ if(sql.startsWith('SELECT'))return {rows:[{id:1,username:'test',expiration_date:'2020-01-01',status:'active'}]}; writes.push(sql); }};
  const system=async(cmd,args)=>{if(cmd==='getent')return 'test:x:1001:1001::/:/bin/false';throw Error('system denied');};
  assert.equal((await reconcileAccounts(db,system)).errors,1);assert.equal(writes.length,0);
});
