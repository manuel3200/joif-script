const {test}=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), os=require('node:os'), path=require('node:path');
const security=require('./backend-security');
function fixture(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mivpn-stage2-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); return dir; }
test('account validation prevents command injection and invalid dates', () => {
  const good = { username: 'testuser', password: 'Pass!123456789', expiration_date: '2099-12-01', max_connections: 2 };
  assert.equal(security.validateAccount(good).date, '2099-12-01');
  const hwidAcc = security.validateAccount({ ...good, hwid: 'h9c69d562f2c697f7c15953eb6706e35' });
  assert.equal(hwidAcc.hwid, 'h9c69d562f2c697f7c15953eb6706e35');
  assert.equal(hwidAcc.nativeName, 'h9c69d562f2c697f7c15953eb6706e35');
  assert.equal(hwidAcc.alias, 'testuser');
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
test('session accounting matches exact SSH user across OpenSSH legacy, sshd-session without @, and user-owner formats', () => {
  assert.deepEqual(security.sessions('120 sshd: testuser@notty\n999 sshd: another@pts/0\n123 sshd: testuser [priv]', 'testuser'), { count: 1, time: '0:02:00' });
  assert.deepEqual(security.sessions('185 sshd-session: testuser@notty\n999 sshd-session: another@pts/0\n60 sshd-session: testuser', 'testuser'), { count: 2, time: '0:03:05' });
  assert.deepEqual(security.sessions('USER ELAPSED COMMAND\nroot 185 sshd-session: joif01 [priv]\njoif01 185 sshd-session: joif01\njoif01 40 sshd-session: joif01@notty\njoif01 15 /usr/sbin/dropbear -p 143', 'joif01'), { count: 3, time: '0:03:05' });
});
test('traffic collector parses /proc/pid/io deltas accurately and formats MB/GB', async () => {
  assert.equal(security.formatTrafficBytes(0), '0.00 MB');
  assert.equal(security.formatTrafficBytes(50 * 1024 * 1024), '50.00 MB');
  assert.equal(security.formatTrafficBytes(1.5 * 1024 * 1024 * 1024), '1.50 GB');
  assert.equal(security.parseProcIoBytes('rchar: 2048\nwchar: 4096\n'), 3072);
  let ioTick = 1;
  const collector = security.createTrafficCollector({
    listSessions: async () => security.sessionPids('USER PID ELAPSED COMMAND\nroot 100 50 sshd-session: joif01 [priv]\njoif01 101 50 sshd-session: joif01\njoif01 102 20 sshd-session: joif01@notty'),
    readProcIo: pid => pid === 101 ? `rchar: ${ioTick * 2000}\nwchar: ${ioTick * 2000}\n` : `rchar: ${ioTick * 1000}\nwchar: ${ioTick * 1000}\n`
  });
  const writes = [];
  const mockDb = { async query(sql, params) { writes.push({ sql, params }); } };
  await collector.flushToDb(mockDb);
  assert.deepEqual(writes[0].params, [3000, 'joif01']);
  ioTick = 3;
  await collector.flushToDb(mockDb);
  assert.deepEqual(writes[1].params, [6000, 'joif01']);
});
