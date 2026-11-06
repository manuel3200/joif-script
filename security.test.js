const {test}=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), os=require('node:os'), path=require('node:path');
const security=require('./backend-security');
function fixture(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mivpn-stage2-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); return dir; }
test('account validation prevents command injection and invalid dates', () => {
  const good = { username: 'testuser', password: 'Pass!123456789', expiration_date: '2099-12-01', max_connections: 2 };
  assert.equal(security.validateAccount(good).date, '2099-12-01');
  for (const username of ['root', '-f', 'x;touch file', 'x\nroot']) assert.throws(() => security.validateAccount({ ...good, username }));
  assert.throws(() => security.validateAccount({ ...good, password: 'pass\nroot:evil' }));
  assert.throws(() => security.validateAccount({ ...good, expiration_date: '2099-02-30' }));
  assert.throws(() => security.validateAccount({ ...good, max_connections: -1 }));
});
test('password hashes and session keys are persistent without fixed secrets', t => {
  const saved = security.hashPassword('authorized-password'); assert.notEqual(saved, 'authorized-password');
  assert.ok(security.verifyPassword('authorized-password', saved)); assert.ok(!security.verifyPassword('wrong', saved));
  const dir = fixture(t); assert.equal(security.sessionSecret(dir, {}), security.sessionSecret(dir, {}));
  assert.throws(() => security.sessionSecret(dir, { SESSION_SECRET: 'default_secret_key' }));
});
test('session accounting matches exact SSH user', () => {
  assert.deepEqual(security.sessions('120 sshd: testuser@notty\n999 sshd: another@pts/0\n123 sshd: testuser [priv]', 'testuser'), { count: 1, time: '0:02:00' });
});
